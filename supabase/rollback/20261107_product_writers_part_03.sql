-- Exact original public Product writer/helper definitions. Restore part 3/5.
-- Retains existing function grants when run with CREATE OR REPLACE.
-- Review impact before applying. Captured 2026-11-07.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.publish_product_publication(p_page text, p_source_watermark_at timestamp with time zone, p_n_events bigint, p_members jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_required text[];
  v_count integer;
  v_member jsonb;
  v_kind text;
  v_scope text;
  v_snapshot_id bigint;
  v_kinds text[] := '{}';
  v_scopes text[] := '{}';
  v_snap_ids bigint[] := '{}';
  v_first_scope text := NULL;
  v_idx integer;
  v_snap_kind text;
  v_snap_scope text;
  v_snap_at timestamptz;
  v_snap_events bigint;
  v_publication_id bigint;
  v_existing_id bigint;
  v_existing_members text[];
  v_requested_members text[];
  v_cur_pub_id bigint;
  v_cur_at timestamptz;
  v_cur_events bigint;
  v_has_current boolean;
  v_live_status text;
  v_live_at timestamptz;
  v_live_events bigint;
BEGIN
  -- Shape checks first (no lock: cheap input validation with explicit
  -- messages, before any state is read).
  IF p_page NOT IN ('overview', 'retention') THEN
    RAISE EXCEPTION 'unknown publication page %', p_page;
  END IF;
  IF p_source_watermark_at IS NULL OR p_n_events IS NULL THEN
    RAISE EXCEPTION 'publication generation is required';
  END IF;
  IF jsonb_typeof(p_members) <> 'array' OR jsonb_array_length(p_members) = 0 THEN
    RAISE EXCEPTION 'publication members must be a non-empty array';
  END IF;

  -- Exact required kinds per page. No more, no fewer, no duplicates, no
  -- wrong-page kinds: combined with the length check below this is exact set
  -- equality against the page's kind set.
  v_required := CASE p_page
    WHEN 'overview' THEN ARRAY['overview','overview-funnel','overview-feature-usage','overview-module-mix','overview-friction']
    ELSE ARRAY['retention-summary','retention-heatmap','retention-monthly','churn-trend']
  END;
  v_count := jsonb_array_length(p_members);
  IF v_count <> array_length(v_required, 1) THEN
    RAISE EXCEPTION '% publication requires % members, got %',
      p_page, array_length(v_required, 1), v_count;
  END IF;

  -- Parse members (JSON only; no state read yet). Each entry must name its
  -- kind, its scope and its snapshot; each kind must belong to this page;
  -- scopes must be well-formed and uniform across the page (a page is one
  -- filter set); kinds must be distinct (duplicates rejected explicitly,
  -- not via a downstream primary-key violation).
  FOR v_member IN SELECT * FROM jsonb_array_elements(p_members) LOOP
    v_kind := v_member ->> 'kind';
    v_scope := COALESCE(v_member ->> 'scope_key', '');
    BEGIN
      v_snapshot_id := NULLIF(v_member ->> 'snapshot_id', '')::bigint;
    EXCEPTION WHEN invalid_text_representation THEN
      v_snapshot_id := NULL;
    END;
    IF v_kind IS NULL OR v_kind = '' THEN
      RAISE EXCEPTION 'publication member % is missing kind', v_member;
    END IF;
    IF v_snapshot_id IS NULL THEN
      RAISE EXCEPTION 'publication member % is missing snapshot_id', v_kind;
    END IF;
    IF NOT (v_kind = ANY (v_required)) THEN
      RAISE EXCEPTION 'publication member kind % does not belong to page %; keeping current',
        v_kind, p_page;
    END IF;
    IF v_kind = ANY (v_kinds) THEN
      RAISE EXCEPTION 'publication member kind % is duplicated; keeping current', v_kind;
    END IF;
    IF v_scope !~ '^[a-z0-9|=.-]{0,160}$' THEN
      RAISE EXCEPTION 'publication member scope for kind % is not an allowed scope; keeping current',
        v_kind;
    END IF;
    IF v_first_scope IS NULL THEN
      v_first_scope := v_scope;
    ELSIF v_scope IS DISTINCT FROM v_first_scope THEN
      RAISE EXCEPTION 'publication members span scopes (%) and (%); a page is one scope, keeping current',
        v_first_scope, v_scope;
    END IF;
    v_kinds := v_kinds || v_kind;
    v_scopes := v_scopes || v_scope;
    v_snap_ids := v_snap_ids || v_snapshot_id;
  END LOOP;

  -- Global lock order: page lock first, then the per-kind locks in sorted
  -- (kind, scope) order. activate_product_snapshot() takes a single kind
  -- lock and never the page lock, so no lock cycle is possible; concurrent
  -- per-kind activations for these scopes serialize here instead of
  -- slipping between validation and swap.
  PERFORM pg_advisory_xact_lock(hashtext('page|' || p_page));
  FOR v_kind, v_scope IN
    SELECT DISTINCT u.kind, u.scope
    FROM unnest(v_kinds, v_scopes) AS u(kind, scope)
    ORDER BY 1, 2
  LOOP
    PERFORM pg_advisory_xact_lock(hashtext(v_kind || '|' || v_scope));
  END LOOP;

  -- Member-vs-snapshot checks: every member's kind/scope must match the row
  -- it references, and every referenced row must carry the manifest
  -- generation. A pointer that names a different row than it claims is
  -- rejected; a mixed-generation page is rejected (that spread is the bug
  -- being fixed).
  FOR v_idx IN 1 .. array_length(v_kinds, 1) LOOP
    v_kind := v_kinds[v_idx];
    v_scope := v_scopes[v_idx];
    v_snapshot_id := v_snap_ids[v_idx];
    SELECT s.kind, s.scope_key, s.source_watermark_at, s.n_events
      INTO v_snap_kind, v_snap_scope, v_snap_at, v_snap_events
    FROM public.product_snapshot AS s
    WHERE s.id = v_snapshot_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'publication snapshot % (kind %) does not exist; keeping current',
        v_snapshot_id, v_kind;
    END IF;
    IF v_snap_kind IS DISTINCT FROM v_kind OR v_snap_scope IS DISTINCT FROM v_scope THEN
      RAISE EXCEPTION 'publication member kind % scope % does not match snapshot % (kind % scope %); keeping current',
        v_kind, v_scope, v_snapshot_id, v_snap_kind, v_snap_scope;
    END IF;
    IF v_snap_at IS DISTINCT FROM p_source_watermark_at
       OR v_snap_events IS DISTINCT FROM p_n_events THEN
      RAISE EXCEPTION
        'publication member % snapshot % generation (%, %) differs from manifest (%, %); keeping current',
        v_kind, v_snapshot_id, v_snap_at, v_snap_events,
        p_source_watermark_at, p_n_events;
    END IF;
  END LOOP;

  -- Idempotency: the same (page, generation) published before. Identical
  -- membership returns the existing id (completing an interrupted publish
  -- when the pointer never moved and the generation is still live);
  -- different membership is an explicit conflict, never a silent second row
  -- (the UNIQUE constraint would reject it generically; this names it).
  SELECT p.publication_id INTO v_existing_id
  FROM public.product_publication AS p
  WHERE p.page = p_page
    AND p.source_watermark_at = p_source_watermark_at
    AND p.n_events = p_n_events;
  IF FOUND THEN
    SELECT COALESCE(array_agg(m.kind || '|' || m.scope_key || '|' || m.snapshot_id ORDER BY m.kind, m.scope_key), '{}')
      INTO v_existing_members
    FROM public.product_publication_member AS m
    WHERE m.publication_id = v_existing_id;
    SELECT COALESCE(array_agg(u.kind || '|' || u.scope || '|' || u.snap_id ORDER BY u.kind, u.scope), '{}')
      INTO v_requested_members
    FROM unnest(v_kinds, v_scopes, v_snap_ids) AS u(kind, scope, snap_id);
    IF v_existing_members = v_requested_members THEN
      -- Identical retry. Finish an interrupted publish when that is still
      -- the correct move: the pointer never moved, nothing newer exists,
      -- and the generation is still live. Otherwise return the id as-is:
      -- already current (no-op), superseded (do not regress), or stale
      -- while something else is current (report, do not swap).
      SELECT TRUE, c.publication_id INTO v_has_current, v_cur_pub_id
      FROM public.product_publication_current AS c
      WHERE c.page = p_page;
      IF v_has_current AND v_cur_pub_id = v_existing_id THEN
        RETURN v_existing_id;
      END IF;
      SELECT w.status, w.last_success_at INTO v_live_status, v_live_at
      FROM public.export_watermarks AS w
      WHERE w.job_name = 'incremental';
      SELECT count(*) INTO v_live_events FROM public.events;
      IF v_live_status IS DISTINCT FROM 'ok'
         OR v_live_at IS DISTINCT FROM p_source_watermark_at
         OR v_live_events IS DISTINCT FROM p_n_events THEN
        -- NULL-safe: v_has_current is TRUE or NULL (never FALSE) from the
        -- SELECT ... INTO above, so test explicitly for "no current row".
        IF v_has_current IS DISTINCT FROM TRUE THEN
          RAISE EXCEPTION 'publication generation (at %, events %) is stale and no publication is current; restage, keeping current',
            p_source_watermark_at, p_n_events;
        END IF;
        SELECT p.source_watermark_at, p.n_events
          INTO v_cur_at, v_cur_events
        FROM public.product_publication_current AS c
        JOIN public.product_publication AS p ON p.publication_id = c.publication_id
        WHERE c.page = p_page;
        IF p_source_watermark_at < v_cur_at
           OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
          RETURN v_existing_id;
        END IF;
        RAISE EXCEPTION 'publication generation (at %, events %) is stale; restage, keeping current',
          p_source_watermark_at, p_n_events;
      END IF;
      IF v_has_current THEN
        SELECT p.source_watermark_at, p.n_events
          INTO v_cur_at, v_cur_events
        FROM public.product_publication_current AS c
        JOIN public.product_publication AS p ON p.publication_id = c.publication_id
        WHERE c.page = p_page;
        IF p_source_watermark_at < v_cur_at
           OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
          RETURN v_existing_id;
        END IF;
      END IF;
      INSERT INTO public.product_publication_current AS c
          (page, publication_id)
      VALUES (p_page, v_existing_id)
      ON CONFLICT (page) DO UPDATE
        SET publication_id = EXCLUDED.publication_id,
            swapped_at = now();
      RETURN v_existing_id;
    END IF;
    RAISE EXCEPTION 'publication for page % generation (at %, events %) already exists as publication % with different membership; refusing conflicting retry, keeping current',
      p_page, p_source_watermark_at, p_n_events, v_existing_id;
  END IF;

  -- Out-of-order guard: never move the page pointer backwards. Read under
  -- the page lock taken above, so a concurrent page publisher cannot slip
  -- between this check and the swap below.
  SELECT TRUE, p.source_watermark_at, p.n_events
    INTO v_has_current, v_cur_at, v_cur_events
  FROM public.product_publication_current AS c
  JOIN public.product_publication AS p ON p.publication_id = c.publication_id
  WHERE c.page = p_page;
  IF v_has_current THEN
    IF p_source_watermark_at < v_cur_at
       OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
      RAISE EXCEPTION
        'publication generation (at %, events %) is older than current (at %, events %); keeping current',
        p_source_watermark_at, p_n_events, v_cur_at, v_cur_events;
    END IF;
  END IF;

  -- Candidate validation: every member must satisfy the same gates the
  -- per-kind path enforces (payload shape, completed sync, staged == live,
  -- coverage). A page can never publish what the per-kind path would refuse.
  FOR v_idx IN 1 .. array_length(v_snap_ids, 1) LOOP
    PERFORM public.assert_product_snapshot_publishable(v_snap_ids[v_idx]);
  END LOOP;

  -- Insert the manifest. A concurrent identical publisher wins the UNIQUE
  -- race here; ON CONFLICT DO NOTHING turns that into the idempotent path
  -- above instead of a generic unique-violation.
  INSERT INTO public.product_publication AS p
      (page, source_watermark_at, n_events)
  VALUES (p_page, p_source_watermark_at, p_n_events)
  ON CONFLICT (page, source_watermark_at, n_events) DO NOTHING
  RETURNING p.publication_id INTO v_publication_id;
  IF v_publication_id IS NULL THEN
    SELECT p.publication_id INTO v_existing_id
    FROM public.product_publication AS p
    WHERE p.page = p_page
      AND p.source_watermark_at = p_source_watermark_at
      AND p.n_events = p_n_events;
    SELECT COALESCE(array_agg(m.kind || '|' || m.scope_key || '|' || m.snapshot_id ORDER BY m.kind, m.scope_key), '{}')
      INTO v_existing_members
    FROM public.product_publication_member AS m
    WHERE m.publication_id = v_existing_id;
    SELECT COALESCE(array_agg(u.kind || '|' || u.scope || '|' || u.snap_id ORDER BY u.kind, u.scope), '{}')
      INTO v_requested_members
    FROM unnest(v_kinds, v_scopes, v_snap_ids) AS u(kind, scope, snap_id);
    IF v_existing_members = v_requested_members THEN
      RETURN v_existing_id;
    END IF;
    RAISE EXCEPTION 'publication for page % generation (at %, events %) already exists as publication % with different membership; refusing conflicting retry, keeping current',
      p_page, p_source_watermark_at, p_n_events, v_existing_id;
  END IF;

  FOR v_idx IN 1 .. array_length(v_kinds, 1) LOOP
    INSERT INTO public.product_publication_member AS m
        (publication_id, kind, scope_key, snapshot_id)
    VALUES (v_publication_id, v_kinds[v_idx], v_scopes[v_idx], v_snap_ids[v_idx]);
  END LOOP;

  -- Revalidate before swapping: the warehouse may have advanced while this
  -- transaction validated members and inserted rows. The per-kind locks do
  -- not block the sync, so compare the single live generation once more;
  -- when it moved, the members just validated are stale and the swap must
  -- not happen. The previous publication keeps serving.
  SELECT w.status, w.last_success_at INTO v_live_status, v_live_at
  FROM public.export_watermarks AS w
  WHERE w.job_name = 'incremental';
  SELECT count(*) INTO v_live_events FROM public.events;
  IF v_live_status IS DISTINCT FROM 'ok'
     OR v_live_at IS DISTINCT FROM p_source_watermark_at
     OR v_live_events IS DISTINCT FROM p_n_events THEN
    RAISE EXCEPTION 'warehouse generation advanced during page publication (manifest %, %; live %, %, %); restage, keeping current',
      p_source_watermark_at, p_n_events, v_live_status, v_live_at, v_live_events;
  END IF;
  -- Re-check the pointer under the same page lock: it cannot have moved
  -- (the lock serializes page publishers), but the check makes the swap
  -- provably monotonic rather than assumed so.
  SELECT TRUE, p.source_watermark_at, p.n_events
    INTO v_has_current, v_cur_at, v_cur_events
  FROM public.product_publication_current AS c
  JOIN public.product_publication AS p ON p.publication_id = c.publication_id
  WHERE c.page = p_page;
  IF v_has_current THEN
    IF p_source_watermark_at < v_cur_at
       OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
      RAISE EXCEPTION
        'publication generation (at %, events %) is older than current (at %, events %); keeping current',
        p_source_watermark_at, p_n_events, v_cur_at, v_cur_events;
    END IF;
  END IF;

  INSERT INTO public.product_publication_current AS c
      (page, publication_id)
  VALUES (p_page, v_publication_id)
  ON CONFLICT (page) DO UPDATE
    SET publication_id = EXCLUDED.publication_id,
        swapped_at = now();
  RETURN v_publication_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.record_activity_day_fact()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  action_day date;
BEGIN
  IF NEW.company_id IS NULL
     OR NEW.event_name NOT IN (
       'Upload',
       'Mapping Completed',
       'Saved Template Loaded',
       'Invoice Created',
       'Invoice Bulk Edited',
       'Download-Inv',
       'Preview',
       'Transaction Ledger Updated',
       'Transaction Status',
       'Transaction Type Updated',
       'Transaction Configuration Edited',
       'Vendor Mismatch Resolved',
       'Accounting Sync',
       'Recon Processed',
       'Entity Created',
       'Delete',
       'Download',
       'Export'
     ) THEN
    RETURN NEW;
  END IF;

  action_day := (NEW.event_time AT TIME ZONE 'Asia/Kolkata')::date;
  INSERT INTO public.company_day_action (company_id, action_date)
  VALUES (NEW.company_id, action_day)
  ON CONFLICT DO NOTHING;

  IF NULLIF(btrim(NEW.distinct_id), '') IS NOT NULL
     AND NOT public.is_internal_email(NEW.email) THEN
    INSERT INTO public.person_day_action (company_id, distinct_id, action_date)
    VALUES (NEW.company_id, NEW.distinct_id, action_day)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_companies_fast_cache()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_usage_rows bigint;
  v_user_rows bigint;
  v_company_rows bigint;
  v_watermark timestamptz;
begin
  delete from metrics_private.company_month_module_usage;

  insert into metrics_private.company_month_module_usage (
    company_id, user_key, month_start, module, events
  )
  with classified as (
    select
      e.company_id,
      coalesce(nullif(btrim(e.distinct_id), ''), '__unattributed__') as user_key,
      date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date as month_start,
      public.company_module_for(e.event_name, coalesce(e.properties, '{}'::jsonb)) as module
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where not public.is_internal_email(e.email)
  )
  select company_id, user_key, month_start, module, count(*)::bigint
  from classified
  where module is not null
  group by company_id, user_key, month_start, module;

  get diagnostics v_usage_rows = row_count;

  delete from metrics_private.company_observed_user;

  insert into metrics_private.company_observed_user (
    company_id, user_key, user_email, first_seen_at, last_seen_at
  )
  select
    e.company_id,
    nullif(btrim(e.distinct_id), '') as user_key,
    (
      array_agg(nullif(btrim(e.email), '') order by e.event_time desc, e.insert_id desc)
      filter (where nullif(btrim(e.email), '') is not null)
    )[1] as user_email,
    min(e.event_time),
    max(e.event_time)
  from public.events e
  join public.client_company c on c.company_id = e.company_id
  where nullif(btrim(e.distinct_id), '') is not null
    and not public.is_internal_email(e.email)
  group by e.company_id, nullif(btrim(e.distinct_id), '');

  get diagnostics v_user_rows = row_count;

  delete from metrics_private.company_reporting_identity;

  insert into metrics_private.company_reporting_identity (
    company_id, company_name, is_test, integration, integration_at
  )
  with event_names as (
    select distinct on (e.company_id)
      e.company_id,
      public.company_usable_name(e.properties ->> 'companyName') as company_name
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.properties ? 'companyName'
      and public.company_usable_name(e.properties ->> 'companyName') is not null
    order by e.company_id, e.event_time desc, e.insert_id desc
  ),
  integrations as (
    select distinct on (e.company_id)
      e.company_id,
      case lower(btrim(coalesce(e.properties ->> 'type', '')))
        when 'tally' then 'Tally'
        when 'zoho' then 'Zoho Books'
        when 'zoho books' then 'Zoho Books'
        else 'Unknown'
      end as integration,
      e.event_time as integration_at
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.event_name = 'Integration status'
      and lower(btrim(coalesce(e.properties ->> 'status', ''))) in ('success','successful')
    order by e.company_id, e.event_time desc, e.insert_id desc
  )
  select
    c.company_id,
    coalesce(nullif(btrim(d.company_name), ''), n.company_name, c.company_id),
    coalesce(d.is_test, false),
    coalesce(i.integration, 'Unknown'),
    i.integration_at
  from public.client_company c
  left join public.company_directory d on d.company_uuid::text = c.company_id
  left join event_names n on n.company_id = c.company_id
  left join integrations i on i.company_id = c.company_id;

  get diagnostics v_company_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name = 'incremental' and w.status = 'ok'
  order by w.last_success_at desc
  limit 1;

  delete from metrics_private.company_reporting_meta;
  insert into metrics_private.company_reporting_meta (
    singleton, data_start, data_end, source_watermark_at, refreshed_at
  )
  select
    true,
    min(e.event_time at time zone 'Asia/Kolkata')::date,
    max(e.event_time at time zone 'Asia/Kolkata')::date,
    v_watermark,
    now()
  from public.events e;

  return jsonb_build_object(
    'usage_rows', v_usage_rows,
    'user_rows', v_user_rows,
    'company_rows', v_company_rows,
    'source_watermark_at', v_watermark,
    'refreshed_at', now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_companies_lifecycle_cache()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_company_rows bigint;
  v_user_rows bigint;
  v_usage_rows bigint;
  v_watermark timestamptz;
begin
  delete from metrics_private.company_lifecycle_identity;

  insert into metrics_private.company_lifecycle_identity (
    company_id, company_name, is_test, integration, integration_at
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at,
      case lower(btrim(coalesce(e.properties ->> 'type', '')))
        when 'tally' then 'Tally'
        when 'zoho' then 'Zoho Books'
        when 'zoho books' then 'Zoho Books'
        else 'Unknown'
      end as integration
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.event_name = 'Integration status'
      and lower(btrim(coalesce(e.properties ->> 'status', ''))) in ('success','successful')
      and e.company_id is not null
      and e.company_id <> ''
    order by e.company_id, e.event_time asc, e.insert_id asc
  ),
  event_names as (
    select distinct on (e.company_id)
      e.company_id,
      public.company_usable_name(e.properties ->> 'companyName') as company_name
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.properties ? 'companyName'
      and public.company_usable_name(e.properties ->> 'companyName') is not null
    order by e.company_id, e.event_time desc, e.insert_id desc
  )
  select
    c.company_id,
    coalesce(nullif(btrim(d.company_name), ''), n.company_name, c.company_id),
    coalesce(d.is_test, false),
    fi.integration,
    fi.integration_at
  from public.client_company c
  join first_integration fi on fi.company_id = c.company_id
  left join public.company_directory d on d.company_uuid::text = c.company_id
  left join event_names n on n.company_id = c.company_id;

  get diagnostics v_company_rows = row_count;

  delete from metrics_private.company_lifecycle_user;

  insert into metrics_private.company_lifecycle_user (
    company_id, user_key, user_email, first_seen_at, last_seen_at
  )
  select
    e.company_id,
    nullif(btrim(e.distinct_id), '') as user_key,
    (
      array_agg(nullif(btrim(e.email), '') order by e.event_time desc, e.insert_id desc)
      filter (where nullif(btrim(e.email), '') is not null)
    )[1] as user_email,
    min(e.event_time),
    max(e.event_time)
  from public.events e
  join metrics_private.company_lifecycle_identity i on i.company_id = e.company_id
  where e.event_time >= i.integration_at
    and nullif(btrim(e.distinct_id), '') is not null
    and not public.is_internal_email(e.email)
  group by e.company_id, nullif(btrim(e.distinct_id), '');

  get diagnostics v_user_rows = row_count;

  delete from metrics_private.company_lifecycle_week_module_usage;

  insert into metrics_private.company_lifecycle_week_module_usage (
    company_id, user_key, usage_week, module, events
  )
  with classified as (
    select
      e.company_id,
      coalesce(nullif(btrim(e.distinct_id), ''), '__unattributed__') as user_key,
      (1 + floor(extract(epoch from (e.event_time - i.integration_at)) / 604800))::smallint as usage_week,
      public.company_module_for(e.event_name, coalesce(e.properties, '{}'::jsonb)) as module
    from public.events e
    join metrics_private.company_lifecycle_identity i on i.company_id = e.company_id
    where e.event_time >= i.integration_at
      and e.event_time < i.integration_at + interval '28 days'
      and not public.is_internal_email(e.email)
  )
  select company_id, user_key, usage_week, module, count(*)::bigint
  from classified
  where usage_week between 1 and 4
    and module in ('ap','ar','transactions','gst')
  group by company_id, user_key, usage_week, module;

  get diagnostics v_usage_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name='incremental' and w.status='ok'
  order by w.last_success_at desc
  limit 1;

  delete from metrics_private.company_lifecycle_meta;
  insert into metrics_private.company_lifecycle_meta (
    singleton, first_integration_date, latest_integration_date,
    source_watermark_at, refreshed_at
  )
  select
    true,
    min(i.integration_at at time zone 'Asia/Kolkata')::date,
    max(i.integration_at at time zone 'Asia/Kolkata')::date,
    v_watermark,
    now()
  from metrics_private.company_lifecycle_identity i;

  return jsonb_build_object(
    'company_rows', v_company_rows,
    'user_rows', v_user_rows,
    'usage_rows', v_usage_rows,
    'source_watermark_at', v_watermark,
    'refreshed_at', now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_companies_monthly_cache()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_company_rows bigint;
  v_user_rows bigint;
  v_usage_rows bigint;
  v_watermark timestamptz;
begin
  -- Same-company refresh jobs must not contend with ingest-triggered refreshes.
  if not pg_try_advisory_xact_lock(20261010,11) then
    return jsonb_build_object('refreshed',false,'reason','refresh_already_running');
  end if;

  select w.last_success_at into v_watermark
  from public.export_watermarks w
  where w.job_name='incremental' and w.last_success_at is not null
    and (w.status='ok' or
      (w.status='failed' and w.detail like 'refresh_retention RPC failed:%'))
  order by w.last_success_at desc limit 1;
  if v_watermark is null then
    raise exception 'companies_source_watermark_unavailable';
  end if;

  delete from metrics_private.company_monthly_identity;

  insert into metrics_private.company_monthly_identity (
    company_id, company_name, is_test, integration, integration_at, integration_month
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at,
      date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date as integration_month,
      case lower(btrim(coalesce(e.properties ->> 'type', '')))
        when 'tally' then 'Tally'
        when 'zoho' then 'Zoho Books'
        when 'zoho books' then 'Zoho Books'
        else 'Unknown'
      end as integration
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    where e.event_name='Integration status'
      and lower(btrim(coalesce(e.properties ->> 'status',''))) in ('success','successful')
      and nullif(btrim(e.company_id),'') is not null
    order by e.company_id, e.event_time asc, e.insert_id asc
  ),
  event_names as (
    select distinct on (e.company_id)
      e.company_id,
      public.company_usable_name(e.properties ->> 'companyName') as company_name
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    where e.properties ? 'companyName'
      and public.company_usable_name(e.properties ->> 'companyName') is not null
    order by e.company_id, e.event_time desc, e.insert_id desc
  )
  select
    c.company_id,
    coalesce(nullif(btrim(d.company_name),''),n.company_name,c.company_id),
    coalesce(d.is_test,false),
    fi.integration,
    fi.integration_at,
    fi.integration_month
  from public.client_company c
  join first_integration fi on fi.company_id=c.company_id
  left join public.company_directory d on d.company_uuid::text=c.company_id
  left join event_names n on n.company_id=c.company_id;

  get diagnostics v_company_rows = row_count;

  delete from metrics_private.company_monthly_user;

  insert into metrics_private.company_monthly_user (
    company_id,user_key,user_email,first_seen_at,last_seen_at
  )
  select
    e.company_id,
    nullif(btrim(e.distinct_id),'') as user_key,
    (
      array_agg(nullif(btrim(e.email),'') order by e.event_time desc,e.insert_id desc)
      filter (where nullif(btrim(e.email),'') is not null)
    )[1] as user_email,
    min(e.event_time),
    max(e.event_time)
  from public.events e
  join metrics_private.company_monthly_identity i on i.company_id=e.company_id
  where e.event_time>=i.integration_at
    and nullif(btrim(e.distinct_id),'') is not null
    and not public.is_internal_email(e.email)
  group by e.company_id,nullif(btrim(e.distinct_id),'');

  get diagnostics v_user_rows = row_count;

  delete from metrics_private.company_calendar_month_module_usage;

  insert into metrics_private.company_calendar_month_module_usage (
    company_id,user_key,usage_month,module,events
  )
  with classified as (
    select
      e.company_id,
      coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
      date_trunc('month',e.event_time at time zone 'Asia/Kolkata')::date as usage_month,
      public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
    from public.events e
    join metrics_private.company_monthly_identity i on i.company_id=e.company_id
    where e.event_time>=i.integration_at
      and not public.is_internal_email(e.email)
  )
  select company_id,user_key,usage_month,module,count(*)::bigint
  from classified
  where module in ('ap','ar','transactions','gst')
  group by company_id,user_key,usage_month,module;

  get diagnostics v_usage_rows = row_count;

  delete from metrics_private.company_monthly_meta;

  insert into metrics_private.company_monthly_meta (
    singleton,first_integration_month,data_month,source_watermark_at,refreshed_at
  )
  select
    true,
    min(i.integration_month),
    date_trunc(
      'month',
      coalesce(v_watermark,now()) at time zone 'Asia/Kolkata'
    )::date,
    v_watermark,
    now()
  from metrics_private.company_monthly_identity i;

  return jsonb_build_object(
    'company_rows',v_company_rows,
    'user_rows',v_user_rows,
    'usage_rows',v_usage_rows,
    'source_watermark_at',v_watermark,
    'refreshed_at',now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_companies_monthly_core_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '95s'
AS $function$
DECLARE v_rows bigint;
BEGIN
 IF NOT pg_try_advisory_xact_lock(20261010,12) THEN
  RETURN jsonb_build_object('status','skipped','reason','refresh_already_running');
 END IF;
 IF (SELECT source_watermark_at FROM metrics_private.company_monthly_meta WHERE singleton) IS NULL THEN
  RAISE EXCEPTION 'companies_core_v2_source_watermark_unavailable';
 END IF;
 TRUNCATE metrics_private.company_calendar_month_module_usage_v2;
 INSERT INTO metrics_private.company_calendar_month_module_usage_v2
 (company_id,user_key,usage_month,module,events)
 WITH qualified AS MATERIALIZED(
  SELECT e.company_id,
  coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') user_key,
  date_trunc('month',e.event_time AT TIME ZONE 'Asia/Kolkata')::date usage_month,
  metrics_private.company_work_module_v2(e.event_name,coalesce(e.properties,'{}'::jsonb)) module
  FROM public.events e
  JOIN metrics_private.company_monthly_identity i ON i.company_id=e.company_id
  LEFT JOIN public.company_directory d ON d.company_uuid::text=e.company_id
  CROSS JOIN metrics_private.company_monthly_meta m
  WHERE m.singleton
   AND e.event_time>=i.integration_at
   AND e.ingested_at<=m.source_watermark_at
   AND NOT coalesce(i.is_test,false)
   AND NOT coalesce(d.is_test,false)
   AND NOT public.is_internal_email(e.email)
 )
 SELECT company_id,user_key,usage_month,module,count(*)::bigint
 FROM qualified WHERE module IN('ap','ar','transactions','gst')
 GROUP BY 1,2,3,4;
 GET DIAGNOSTICS v_rows=ROW_COUNT;

 INSERT INTO metrics_private.company_monthly_meta_v2
 (singleton,first_integration_month,data_month,source_watermark_at,refreshed_at)
 SELECT true, min(i.integration_month) FILTER(WHERE NOT i.is_test),
   max(m.data_month),max(m.source_watermark_at),now()
 FROM metrics_private.company_monthly_meta m
 LEFT JOIN metrics_private.company_monthly_identity i ON NOT i.is_test
 WHERE m.singleton
 ON CONFLICT(singleton) DO UPDATE SET
 first_integration_month=excluded.first_integration_month,
 data_month=excluded.data_month,
 source_watermark_at=excluded.source_watermark_at,
 refreshed_at=excluded.refreshed_at;

 RETURN jsonb_build_object('status','ok','usage_rows',v_rows,
 'source_watermark_at',(SELECT source_watermark_at FROM metrics_private.company_monthly_meta_v2 WHERE singleton));
END;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_company_week_product(p_source text DEFAULT 'public.events'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  src text;
  inserted_count integer;
BEGIN
  IF p_source NOT IN ('public.events', 'metrics_scratch.events') THEN
    RAISE EXCEPTION 'refusing unsafe source table name: %', p_source;
  END IF;
  src := p_source;

  TRUNCATE TABLE public.company_week_product;

  EXECUTE format(
    $q$
    WITH flagged AS (
      SELECT
        e.company_id,
        (date_trunc('week', e.event_time AT TIME ZONE 'Asia/Kolkata'))::date
          AS week_start,
        (
          e.event_name = 'Upload'
          AND e.properties->>'type' = 'invoice'
          AND e.properties->>'status' IS DISTINCT FROM 'Failed'
        ) AS had_uploaded_excel,
        (
          (
            e.event_name = 'Entity Created'
            AND e.properties->>'entityType' = 'bill'
          )
          OR (
            e.event_name IN ('Upload', 'Download')
            AND e.properties->>'type' = 'bill'
            AND (
              e.event_name <> 'Upload'
              OR e.properties->>'status' IS DISTINCT FROM 'Failed'
            )
          )
        ) AS had_ap_active,
        (
          (
            e.event_name IN ('Upload', 'Download')
            AND e.properties->>'type' = 'statement'
            AND (
              e.event_name <> 'Upload'
              OR e.properties->>'status' IS DISTINCT FROM 'Failed'
            )
          )
          OR e.event_name IN ('Transaction Status', 'Txn Category Updated')
        ) AS had_txn_active,
        (
          (
            e.event_name = 'Upload'
            AND e.properties->>'type' IN ('gstr2b', 'purchase_register')
            AND e.properties->>'status' IS DISTINCT FROM 'Failed'
          )
          OR e.event_name = 'Recon Processed'
          OR (
            e.event_name = 'Download'
            AND e.properties->>'type' = 'reconciled_excel'
          )
        ) AS had_gst_recon,
        (
          (
            e.event_name = 'Entity Created'
            AND e.properties->>'entityType' = 'bill'
          )
          OR (
            e.event_name = 'Transaction Status'
            AND e.properties->>'status' = 'Accounting Ready'
          )
        ) AS had_created_bill_or_txn,
        (
          e.event_name = 'Upload'
          AND e.properties->>'type' = 'bill'
          AND e.properties->>'status' IS DISTINCT FROM 'Failed'
        ) AS had_bill_upload,
        (
          e.event_name = 'Upload'
          AND e.properties->>'type' = 'invoice'
          AND e.properties->>'status' IS DISTINCT FROM 'Failed'
        ) AS had_invoice_upload,
        (
          e.event_name = 'Upload'
          AND e.properties->>'type' = 'statement'
          AND e.properties->>'status' IS DISTINCT FROM 'Failed'
        ) AS had_statement_upload
      FROM %s AS e
      WHERE e.company_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.client_company AS c
          WHERE c.company_id = e.company_id
        )
    ), grouped AS (
      SELECT
        company_id,
        week_start,
        BOOL_OR(had_uploaded_excel) AS had_uploaded_excel,
        BOOL_OR(had_ap_active) AS had_ap_active,
        BOOL_OR(had_txn_active) AS had_txn_active,
        BOOL_OR(had_gst_recon) AS had_gst_recon,
        BOOL_OR(had_created_bill_or_txn) AS had_created_bill_or_txn,
        BOOL_OR(had_bill_upload) AS had_bill_upload,
        BOOL_OR(had_invoice_upload) AS had_invoice_upload,
        BOOL_OR(had_statement_upload) AS had_statement_upload
      FROM flagged
      GROUP BY company_id, week_start
    )
    INSERT INTO public.company_week_product (
      company_id, week_start,
      had_uploaded_excel, had_ap_active, had_txn_active,
      had_gst_recon, had_created_bill_or_txn,
      had_bill_upload, had_invoice_upload, had_statement_upload
    )
    SELECT
      company_id, week_start,
      had_uploaded_excel, had_ap_active, had_txn_active,
      had_gst_recon, had_created_bill_or_txn,
      had_bill_upload, had_invoice_upload, had_statement_upload
    FROM grouped
    WHERE had_uploaded_excel
       OR had_ap_active
       OR had_txn_active
       OR had_gst_recon
       OR had_created_bill_or_txn
       OR had_bill_upload
       OR had_invoice_upload
       OR had_statement_upload
    $q$, src
  );
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$function$
;
