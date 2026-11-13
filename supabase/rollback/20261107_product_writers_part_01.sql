-- Exact original public Product writer/helper definitions. Restore part 1/5.
-- Retains existing function grants when run with CREATE OR REPLACE.
-- Review impact before applying. Captured 2026-11-07.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.activate_product_snapshot(p_snapshot_id bigint, p_min_client_companies integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_kind text;
  v_scope text;
  v_staged_at timestamptz;
  v_staged_events bigint;
  v_cur_at timestamptz;
  v_cur_events bigint;
  v_cur_id bigint;
  v_has_current boolean;
BEGIN
  -- Resolve the candidate's identity FIRST. The (kind, scope_key) lock key is
  -- derived from the row, and both columns are immutable for a given id, so
  -- reading them here cannot race with anything this function later guards.
  SELECT s.kind, s.scope_key
    INTO v_kind, v_scope
  FROM public.product_snapshot AS s
  WHERE s.id = p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product snapshot % does not exist', p_snapshot_id;
  END IF;

  -- THE LOCK COMES BEFORE EVERY STATE READ (Brief 04 review fix). Publishability
  -- validation (payload, completed sync, staged == live, coverage) and the
  -- generation-ordering read both depend on live state, so taking the lock
  -- first makes the whole validate-and-swap sequence one critical section per
  -- (kind, scope_key). Previously both ran BEFORE the lock, so two overlapping
  -- activations could each validate against the pre-advance warehouse and read
  -- "no current", and the OLDER one could then swap last — reproduced as a
  -- pointer regression from snapshot 161 to snapshot 160.
  --
  -- The same lock expression the page manifest uses (hashtext(kind||'|'||scope)
  -- is exactly the value page publication locks per member), so a page
  -- publication in flight blocks per-kind activations for its kinds and vice
  -- versa. activate never takes the page lock, so no lock cycle exists.
  -- Brief 06 immutability: the snapshot lock comes FIRST, then the scope
  -- lock — the same order stage_funnel_members uses. One shared order means
  -- a staging in flight for this snapshot cannot interleave with the
  -- validate-and-swap below (whoever takes the snapshot lock first runs its
  -- whole body before the other starts), and no wait cycle can form: the
  -- page-publication path ends on the scope lock too and never takes a
  -- snapshot lock.
  PERFORM pg_advisory_xact_lock(p_snapshot_id);
  PERFORM pg_advisory_xact_lock(hashtext(v_kind || '|' || v_scope));

  -- Gates run under the lock: a warehouse generation advance or a competing
  -- activation that landed while this session waited is seen here, so a stale
  -- candidate can no longer slip through on a pre-lock reading.
  PERFORM public.assert_product_snapshot_publishable(
    p_snapshot_id, p_min_client_companies);

  SELECT s.source_watermark_at, s.n_events
    INTO v_staged_at, v_staged_events
  FROM public.product_snapshot AS s
  WHERE s.id = p_snapshot_id;

  -- Generation ordering, read under the same lock (so it cannot be stale by
  -- the time of the swap):
  --   1. an older warehouse generation never replaces a newer one;
  --   2. within ONE generation (equal watermark and event count), a candidate
  --      staged earlier never replaces one staged later — snapshot ids are
  --      monotonic, so the newest staged candidate wins. Re-activating the
  --      current row is idempotent (same id, no id tie-break applies).
  -- Legacy NULL-generation rows skip comparison 1 (back-compat) as before.
  SELECT TRUE, s.source_watermark_at, s.n_events, s.id
    INTO v_has_current, v_cur_at, v_cur_events, v_cur_id
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = v_kind AND c.scope_key = v_scope;
  IF v_has_current AND v_staged_at IS NOT NULL AND v_cur_at IS NOT NULL THEN
    IF v_staged_at < v_cur_at
       OR (v_staged_at = v_cur_at
           AND v_staged_events IS NOT NULL AND v_cur_events IS NOT NULL
           AND v_staged_events < v_cur_events) THEN
      RAISE EXCEPTION
        'staged generation (at %, events %) is older than current (at %, events %); keeping current',
        v_staged_at, v_staged_events, v_cur_at, v_cur_events;
    END IF;
    IF v_staged_at = v_cur_at
       AND v_staged_events IS NOT DISTINCT FROM v_cur_events
       AND p_snapshot_id < v_cur_id THEN
      RAISE EXCEPTION
        'staged candidate % is older than current snapshot % for the same generation (at %, events %); keeping current',
        p_snapshot_id, v_cur_id, v_staged_at, v_staged_events;
    END IF;
  END IF;

  INSERT INTO public.product_snapshot_current AS c
      (kind, scope_key, snapshot_id)
  VALUES (v_kind, v_scope, p_snapshot_id)
  ON CONFLICT (kind, scope_key) DO UPDATE
    SET snapshot_id = EXCLUDED.snapshot_id,
        published_at = now();

  -- Brief 06 immutability: a funnel candidate publishes ONLY with a
  -- completed membership set (stage_funnel_members seals the set when it
  -- completes; activation requires that seal). Publishing an incomplete
  -- candidate here would strand a memberless current generation whose real
  -- set could then never stage (the sealed-empty wedge), so it is refused
  -- instead: last good generation keeps serving and the publish fails
  -- loudly. Seals of OTHER snapshots — the retained older generation just
  -- displaced, any other scope — are untouched: every published generation
  -- stays immutable.
  --
  -- The funnel table is probed via to_regclass and the static reference
  -- nested behind it: a database without the funnel migration must keep the
  -- old behavior, and plpgsql plans a statement when EXECUTED, so the
  -- guarded branch never plans a missing relation.
  -- SEPARATE statements: plpgsql plans one statement when it executes it, so
  -- the seal query must live in its own IF to stay unplaned on databases
  -- without the funnel migration.
  IF v_kind = 'overview-funnel'
     AND to_regclass('public.product_funnel_seal') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.product_funnel_seal AS x
      WHERE x.snapshot_id = p_snapshot_id
    ) THEN
      RAISE EXCEPTION
        'funnel candidate % has no completed membership set; stage_funnel_members first',
        p_snapshot_id;
    END IF;
  ELSIF v_kind IN ('overview', 'overview-feature-usage', 'overview-module-mix', 'overview-friction')
     AND to_regclass('public.product_overview_seal') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.product_overview_seal AS x
      WHERE x.snapshot_id = p_snapshot_id
    ) THEN
      RAISE EXCEPTION
        'overview candidate % has no completed membership set; stage_overview_members first',
        p_snapshot_id;
    END IF;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.assert_product_snapshot_publishable(p_snapshot_id bigint, p_min_client_companies integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_staged_status text;
  v_staged_at timestamptz;
  v_staged_events bigint;
  v_live_status text;
  v_live_at timestamptz;
  v_live_events bigint;
  v_live_client integer;
BEGIN
  SELECT s.source_status, s.source_watermark_at, s.n_events
    INTO v_staged_status, v_staged_at, v_staged_events
  FROM public.product_snapshot AS s
  WHERE s.id = p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product snapshot % does not exist', p_snapshot_id;
  END IF;

  -- Re-assert payload shape at promotion time (belt and braces over the
  -- table CHECK) so no future path can promote an empty payload.
  PERFORM 1
  FROM public.product_snapshot AS s
  WHERE s.id = p_snapshot_id
    AND jsonb_typeof(s.payload) = 'object'
    AND s.payload <> '{}'::jsonb;
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'product snapshot % has an incomplete payload; keeping current',
      p_snapshot_id;
  END IF;

  -- Gate 1: the incremental sync must have COMPLETED successfully. The lease
  -- RPC overwrites last_success_at when a run starts and finish_incremental
  -- sets status='failed' on error, so a running or failed sync can never
  -- satisfy this gate, and its failure keeps the last good pointer.
  SELECT w.status, w.last_success_at
    INTO v_live_status, v_live_at
  FROM public.export_watermarks AS w
  WHERE w.job_name = 'incremental';
  IF v_live_status IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION
      'incremental sync status is %, not ok; keeping current',
      COALESCE(v_live_status, 'missing');
  END IF;

  -- Gate 2: the staged generation must still BE the live generation: same
  -- completed sync instant AND same event count. A newer successful sync
  -- means restage, never silent promotion of a payload computed from older
  -- data.
  SELECT count(*) INTO v_live_events FROM public.events;
  IF NOT (v_staged_status IS NOT DISTINCT FROM v_live_status
      AND v_staged_at IS NOT DISTINCT FROM v_live_at
      AND v_staged_events IS NOT DISTINCT FROM v_live_events) THEN
    RAISE EXCEPTION
      'warehouse generation changed between stage and activate '
      '(staged status/at/events=%,%,%; live=%,%,%); restage, keeping current',
      v_staged_status, v_staged_at, v_staged_events,
      v_live_status, v_live_at, v_live_events;
  END IF;

  -- Gate 3: the warehouse must still describe a real population.
  SELECT count(*)::int INTO v_live_client FROM public.client_company;
  IF v_live_client < COALESCE(p_min_client_companies, 1) THEN
    RAISE EXCEPTION
      'warehouse coverage too low (client companies=%, minimum=%); keeping current',
      v_live_client, COALESCE(p_min_client_companies, 1);
  END IF;
  IF EXISTS(SELECT 1 FROM public.product_snapshot WHERE id=p_snapshot_id AND kind='retention-summary' AND scope_key='') THEN
    IF NOT EXISTS(SELECT 1 FROM public.product_retention_summary_seal WHERE snapshot_id=p_snapshot_id) THEN
      RAISE EXCEPTION 'retention summary has no completed membership set';
    END IF;
  END IF;
  IF EXISTS(SELECT 1 FROM public.product_snapshot WHERE id=p_snapshot_id AND kind IN ('retention-heatmap','retention-monthly','churn-trend') AND scope_key='') THEN
    IF NOT EXISTS(SELECT 1 FROM public.product_retention_period_seal WHERE snapshot_id=p_snapshot_id) THEN
      RAISE EXCEPTION 'retention period has no completed membership set';
    END IF;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.begin_product_refresh(p_kind text, p_scope_key text, p_build_key text, p_watermark_at timestamp with time zone, p_n_events bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id bigint;
BEGIN
  IF p_build_key IS NULL OR btrim(p_build_key) = '' THEN
    RAISE EXCEPTION 'build_key is required';
  END IF;
  INSERT INTO public.product_refresh_run AS r
      (kind, scope_key, build_key, status, source_watermark_at, n_events)
  VALUES (p_kind, COALESCE(p_scope_key, ''), p_build_key,
          'building', p_watermark_at, p_n_events)
  ON CONFLICT (kind, scope_key, build_key) DO UPDATE
    SET status = CASE
            WHEN r.status = 'failed' THEN 'building'
            ELSE r.status
          END,
        source_watermark_at = COALESCE(EXCLUDED.source_watermark_at, r.source_watermark_at),
        n_events = COALESCE(EXCLUDED.n_events, r.n_events),
        updated_at = now()
  RETURNING id INTO v_id;
  -- ON CONFLICT DO UPDATE always returns a row, but a DO NOTHING race on a
  -- concurrent insert needs the follow-up select. Keep it for safety.
  IF v_id IS NULL THEN
    SELECT r.id INTO v_id
    FROM public.product_refresh_run AS r
    WHERE r.kind = p_kind
      AND r.scope_key = COALESCE(p_scope_key, '')
      AND r.build_key = p_build_key;
  END IF;
  RETURN v_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.claim_retention_period_build(p_kind text, p_token uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE won boolean;
BEGIN
 INSERT INTO product_retention_build_lease VALUES(p_kind,p_token,clock_timestamp()+interval '5 minutes')
 ON CONFLICT(kind) DO UPDATE SET token=excluded.token,expires_at=excluded.expires_at
 WHERE product_retention_build_lease.expires_at<clock_timestamp()
 RETURNING true INTO won;
 RETURN coalesce(won,false);
END $function$
;

CREATE OR REPLACE FUNCTION public.company_items_for(p_event_name text, p_properties jsonb)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_event_name = 'Accounting Sync'
         AND jsonb_typeof(p_properties -> 'items_count') = 'number'
      THEN (p_properties ->> 'items_count')::bigint
    WHEN p_event_name = 'Transaction Status'
         AND jsonb_typeof(p_properties -> 'itemsCount') = 'number'
      THEN (p_properties ->> 'itemsCount')::bigint
    WHEN p_event_name IN ('Transaction Ledger Updated', 'Transaction Type Updated')
         AND jsonb_typeof(p_properties -> 'transactionCount') = 'number'
      THEN (p_properties ->> 'transactionCount')::bigint
    ELSE NULL
  END
$function$
;

CREATE OR REPLACE FUNCTION public.company_module_for(p_event_name text, p_properties jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN (p_event_name IN ('Upload', 'Delete', 'Download')
          AND lower(p_properties ->> 'type') = 'bill')
      OR (p_event_name = 'Entity Created'
          AND lower(p_properties ->> 'entityType') = 'bill')
      OR p_event_name IN ('Invoice Bulk Edited', 'Vendor Mismatch Resolved')
      THEN 'ap'
    WHEN (p_event_name IN ('Upload', 'Download')
          AND lower(p_properties ->> 'type') = 'invoice')
      OR (p_event_name = 'Entity Created'
          AND lower(p_properties ->> 'entityType') = 'invoice')
      OR p_event_name IN ('Invoice Created', 'Download-Inv', 'Preview')
      THEN 'ar'
    WHEN (p_event_name IN ('Upload', 'Download')
          AND lower(p_properties ->> 'type') = 'statement')
      OR p_event_name IN ('Transaction Ledger Updated', 'Transaction Status',
                          'Transaction Type Updated',
                          'Transaction Configuration Edited')
      THEN 'transactions'
    WHEN (p_event_name = 'Upload'
          AND lower(p_properties ->> 'type') IN ('gstr2b', 'purchase_register'))
      OR p_event_name = 'Recon Processed'
      OR (p_event_name = 'Download'
          AND lower(p_properties ->> 'type') = 'reconciled_excel')
      OR (p_event_name = 'Export'
          AND lower(p_properties ->> 'type') = 'gst_reconciliation')
      THEN 'gst'
    WHEN p_event_name = 'Accounting Sync'
      THEN 'sync'
    ELSE NULL
  END
$function$
;

CREATE OR REPLACE FUNCTION public.company_subtype_for(p_event_name text, p_properties jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_event_name IN ('Upload', 'Delete', 'Download', 'Download-Inv',
                          'Export', 'Preview')
      THEN NULLIF(btrim(p_properties ->> 'type'), '')
    WHEN p_event_name = 'Entity Created'
      THEN NULLIF(btrim(p_properties ->> 'entityType'), '')
    WHEN p_event_name IN ('Transaction Ledger Updated', 'Transaction Type Updated')
      THEN NULLIF(
             concat_ws(' → ',
               NULLIF(btrim(p_properties ->> 'from'), ''),
               NULLIF(btrim(p_properties ->> 'to'), '')),
             '')
    WHEN p_event_name = 'Transaction Configuration Edited'
      THEN NULLIF(btrim(p_properties ->> 'configField'), '')
    WHEN p_event_name = 'Vendor Mismatch Resolved'
      THEN NULLIF(btrim(p_properties ->> 'resolutionType'), '')
    WHEN p_event_name = 'Accounting Sync'
      THEN (SELECT string_agg(value, ', ')
            FROM jsonb_array_elements_text(p_properties -> 'sync_items') AS value
            WHERE NULLIF(btrim(value), '') IS NOT NULL)
    ELSE NULL
  END
$function$
;

CREATE OR REPLACE FUNCTION public.company_usable_name(p_raw text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN NULLIF(btrim(p_raw), '') IS NULL THEN NULL
    WHEN lower(btrim(p_raw)) IN (
      'abc', 'dummy', 'na', 'n/a', 'test', 'testing', 'demo', 'xyz',
      'delete company') THEN NULL
    ELSE btrim(p_raw)
  END
$function$
;

CREATE OR REPLACE FUNCTION public.complete_product_refresh(p_run_id bigint, p_staged_snapshot_id bigint, p_status text DEFAULT 'staged'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_status NOT IN ('staged', 'published', 'superseded') THEN
    RAISE EXCEPTION 'invalid terminal status %', p_status;
  END IF;
  UPDATE public.product_refresh_run AS r
  SET status = p_status,
      staged_snapshot_id = p_staged_snapshot_id,
      updated_at = now()
  WHERE r.id = p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product refresh run % does not exist', p_run_id;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.core_activity_kind(p_event_name text, p_properties jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT CASE
    WHEN p_event_name = 'Upload'
      AND lower(btrim(COALESCE(p_properties->>'type', '')))
          IN ('bill', 'invoice', 'statement')
      THEN 'upload'
    WHEN p_event_name = 'Entity Created'
      AND lower(btrim(COALESCE(p_properties->>'entityType', '')))
          IN ('bill', 'invoice')
      THEN 'entity'
    WHEN p_event_name IN (
      'Invoice Bulk Edited',
      'Transaction Ledger Updated',
      'Transaction Status',
      'Transaction Type Updated',
      'Transaction Configuration Edited',
      'Vendor Mismatch Resolved',
      'Accounting Sync'
    )
      THEN 'workflow'
    ELSE NULL
  END;
$function$
;

CREATE OR REPLACE FUNCTION public.fail_product_refresh(p_run_id bigint, p_error_code text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.product_refresh_run AS r
  SET status = 'failed',
      error_code = p_error_code,
      detail = p_detail,
      updated_at = now()
  WHERE r.id = p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product refresh run % does not exist', p_run_id;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.finish_incremental(p_ok boolean, p_day date, p_detail text)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE public.export_watermarks
  SET last_success_date = CASE WHEN p_ok THEN p_day ELSE last_success_date END,
      last_success_at = now(),
      status = CASE WHEN p_ok THEN 'ok' ELSE 'failed' END,
      detail = p_detail
  WHERE job_name = 'incremental';
$function$
;

CREATE OR REPLACE FUNCTION public.is_core_activity(p_event_name text, p_properties jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT public.core_activity_kind(p_event_name, p_properties) IS NOT NULL;
$function$
;

CREATE OR REPLACE FUNCTION public.is_internal_email(p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE
AS $function$
DECLARE
  raw text;
  last_lt int;
  last_gt int;
  domain text;
BEGIN
  IF p_email IS NULL OR btrim(p_email) = '' THEN
    RETURN false;
  END IF;
  raw := lower(btrim(p_email));
  last_lt := CASE
    WHEN strpos(raw, '<') = 0 THEN 0
    ELSE length(raw) - strpos(reverse(raw), '<') + 1
  END;
  last_gt := CASE
    WHEN strpos(raw, '>') = 0 THEN 0
    ELSE length(raw) - strpos(reverse(raw), '>') + 1
  END;
  IF last_lt > 0 AND last_gt > 0 THEN
    raw := btrim(
      substring(
        raw
        FROM last_lt + 1
        FOR GREATEST(last_gt - last_lt - 1, 0)
      )
    );
  END IF;
  IF strpos(raw, '@') = 0 THEN
    RETURN false;
  END IF;
  domain := substring(raw FROM length(raw) - strpos(reverse(raw), '@') + 2);
  RETURN domain IN (
        'karboncard.com',
        'korefi.ai',
        'aiaccountant.com',
        'korefi.com'
      )
      OR domain LIKE '%.karboncard.com'
      OR domain LIKE '%.korefi.ai'
      OR domain LIKE '%.aiaccountant.com'
      OR domain LIKE '%.korefi.com';
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_qualifying_sync(p_event_name text, p_properties jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT CASE
    WHEN p_event_name IS DISTINCT FROM 'Accounting Sync' THEN false
    WHEN jsonb_typeof(p_properties->'items_count') IS DISTINCT FROM 'number'
      THEN false
    ELSE COALESCE((p_properties->>'items_count')::numeric > 0, false)
  END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_successful_integration(p_event_name text, p_properties jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT p_event_name = 'Integration status'
     AND lower(btrim(COALESCE(p_properties->>'status', '')))
         IN ('success', 'successful')
     AND lower(btrim(COALESCE(p_properties->>'type', '')))
         IN ('tally', 'zoho');
$function$
;

CREATE OR REPLACE FUNCTION public.merge_event_properties(p_old jsonb, p_new jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT COALESCE(p_old, '{}'::jsonb) || COALESCE(p_new, '{}'::jsonb)
$function$
;
