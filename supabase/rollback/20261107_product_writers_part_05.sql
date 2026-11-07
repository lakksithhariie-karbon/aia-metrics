-- Exact original public Product writer/helper definitions. Restore part 5/5.
-- Retains existing function grants when run with CREATE OR REPLACE.
-- Review impact before applying. Captured 2026-11-07.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.stage_funnel_members(p_snapshot_id bigint, p_members jsonb, p_headers jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_members integer;
  v_headers integer;
  v_kind text;
  v_scope text;
  v_is_current boolean;
  v_is_sealed boolean;
  v_is_publication_member boolean;
  v_incoming text;
  v_stored text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.product_snapshot AS s WHERE s.id = p_snapshot_id) THEN
    RAISE EXCEPTION 'product snapshot % does not exist', p_snapshot_id;
  END IF;
  IF jsonb_typeof(p_members) <> 'array' THEN
    RAISE EXCEPTION 'funnel members must be a JSON array';
  END IF;
  IF jsonb_typeof(p_headers) <> 'array' THEN
    RAISE EXCEPTION 'funnel drill headers must be a JSON array';
  END IF;

  -- ONE LOCKING PROTOCOL, shared with activation: snapshot lock first, then
  -- the snapshot's scope lock (the same derived key activation holds while it
  -- orders and flips the pointer). Activation never takes the snapshot lock,
  -- so this order cannot cycle: a stager waiting on the scope lock waits for
  -- the activator to finish, and the activator never waits on a stager that
  -- holds the snapshot lock and wants the scope lock UNLESS the activator
  -- also wanted the snapshot lock — it does not. Distinct snapshots contend
  -- only on their scope, interleaving cleanly.
  PERFORM pg_advisory_xact_lock(p_snapshot_id);
  SELECT s.kind, s.scope_key INTO v_kind, v_scope
  FROM public.product_snapshot AS s WHERE s.id = p_snapshot_id;
  PERFORM pg_advisory_xact_lock(hashtext(v_kind || '|' || v_scope));

  -- A snapshot's membership is influential — immutable — when ANY of these
  -- holds: it carries a seal (its set completed: published, retained as an
  -- older generation, or staged-complete and possibly mid-publication), it
  -- is the current pointer for its scope, or it is held by a page
  -- publication. The seal is what protects retained generations; the
  -- pointer and the publication follow from the generations contract.
  SELECT EXISTS (
    SELECT 1 FROM public.product_funnel_seal AS x
    WHERE x.snapshot_id = p_snapshot_id
  ) INTO v_is_sealed;
  SELECT EXISTS (
    SELECT 1 FROM public.product_snapshot_current AS c
    WHERE c.snapshot_id = p_snapshot_id
  ) INTO v_is_current;
  -- to_regclass guard: a database without the generations migration has no
  -- publication table; plpgsql plans a statement when executed, so the
  -- static reference must sit behind the probe.
  IF to_regclass('public.product_publication_member') IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.product_publication_member AS m
      WHERE m.snapshot_id = p_snapshot_id
    ) INTO v_is_publication_member;
  END IF;
  -- (Same plpgsql rule as activation's guard: the guarded SELECT is its own
  -- statement, so the publication reference is never planned when absent.)

  IF COALESCE(v_is_sealed, false) OR COALESCE(v_is_current, false)
     OR COALESCE(v_is_publication_member, false) THEN
    -- Published data never changes in place: compare canonical content.
    -- Both sides go through jsonb output text, so key order cannot fake a
    -- difference (or hide one); lines are ordered, so row order cannot
    -- either. Multiset equality per side, then both sides must agree.
    SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_incoming
    FROM (
      SELECT ((x.member->>'node_key') || '|' || (x.member->>'tab') || '|' || (x.member->>'company_id') || '|'
              || ((x.member->>'position')) || '|' || ((x.member->'card')::text)) AS line
      FROM jsonb_array_elements(p_members) AS x(member)
    ) AS m;
    SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_stored
    FROM (
      SELECT (y.node_key || '|' || y.tab || '|' || y.company_id || '|'
              || y.sort_position || '|' || y.card::text) AS line
      FROM public.product_funnel_member AS y
      WHERE y.snapshot_id = p_snapshot_id
    ) AS s;
    IF v_incoming IS NOT DISTINCT FROM v_stored THEN
      SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_incoming
      FROM (
        SELECT ((x.header->>'node_key') || '|' || (x.header->>'tab') || '|' || ((x.header->'header')::text)) AS line
        FROM jsonb_array_elements(p_headers) AS x(header)
      ) AS h;
      SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_stored
      FROM (
        SELECT (y.node_key || '|' || y.tab || '|' || y.header::text) AS line
        FROM public.product_funnel_drill AS y
        WHERE y.snapshot_id = p_snapshot_id
      ) AS s;
    END IF;
    IF v_incoming IS NOT DISTINCT FROM v_stored THEN
      -- Identical retry: safe no-op returning the existing counts. (A
      -- pathological md5 collision could falsely accept different content as
      -- identical — it does not guarantee the retry was actually identical;
      -- the hash covers the full canonical content and the probability is
      -- negligible; swap to sha256 if airtight hashing is preferred.)
      SELECT count(*) INTO v_members FROM public.product_funnel_member WHERE snapshot_id = p_snapshot_id;
      SELECT count(*) INTO v_headers FROM public.product_funnel_drill WHERE snapshot_id = p_snapshot_id;
      RETURN v_members + v_headers;
    END IF;
    RAISE EXCEPTION
      'funnel membership for published snapshot % is immutable; differing content requires a new candidate',
      p_snapshot_id;
  END IF;

  DELETE FROM public.product_funnel_member AS m WHERE m.snapshot_id = p_snapshot_id;
  DELETE FROM public.product_funnel_drill AS d WHERE d.snapshot_id = p_snapshot_id;

  INSERT INTO public.product_funnel_member
      (snapshot_id, node_key, tab, company_id, sort_position, card)
  SELECT p_snapshot_id,
         m.member->>'node_key', m.member->>'tab', m.member->>'company_id',
         (m.member->>'position')::integer, m.member->'card'
  FROM jsonb_array_elements(p_members) WITH ORDINALITY AS m(member, ord);
  GET DIAGNOSTICS v_members = ROW_COUNT;

  INSERT INTO public.product_funnel_drill
      (snapshot_id, node_key, tab, header)
  SELECT p_snapshot_id, h.header->>'node_key', h.header->>'tab', h.header->'header'
  FROM jsonb_array_elements(p_headers) WITH ORDINALITY AS h(header, ord);
  GET DIAGNOSTICS v_headers = ROW_COUNT;

  -- Seal: this snapshot's set is now COMPLETE. From here on the snapshot is
  -- influential for rule 2; activation replaces the seal row at the pointer
  -- flip, so an old current loses its seal when it stops being live data and
  -- a newly-flipped current always has one.
  INSERT INTO public.product_funnel_seal (snapshot_id) VALUES (p_snapshot_id)
  ON CONFLICT (snapshot_id) DO NOTHING;

  RETURN v_members + v_headers;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.stage_overview_members(p_snapshot_id bigint, p_members jsonb, p_headers jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_members integer;
  v_headers integer;
  v_kind text;
  v_scope text;
  v_is_current boolean;
  v_is_sealed boolean;
  v_is_publication_member boolean;
  v_incoming text;
  v_stored text;
BEGIN
  SELECT s.kind, s.scope_key INTO v_kind, v_scope
  FROM public.product_snapshot AS s WHERE s.id = p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product snapshot % does not exist', p_snapshot_id;
  END IF;
  IF v_kind NOT IN ('overview', 'overview-feature-usage', 'overview-module-mix', 'overview-friction') THEN
    RAISE EXCEPTION 'stage_overview_members: kind % not allowed', v_kind;
  END IF;
  IF jsonb_typeof(p_members) <> 'array' THEN
    RAISE EXCEPTION 'overview members must be a JSON array';
  END IF;
  IF jsonb_typeof(p_headers) <> 'array' THEN
    RAISE EXCEPTION 'overview drill headers must be a JSON array';
  END IF;

  PERFORM pg_advisory_xact_lock(p_snapshot_id);
  PERFORM pg_advisory_xact_lock(hashtext(v_kind || '|' || v_scope));

  SELECT EXISTS (SELECT 1 FROM public.product_overview_seal AS x WHERE x.snapshot_id = p_snapshot_id) INTO v_is_sealed;
  SELECT EXISTS (SELECT 1 FROM public.product_snapshot_current AS c WHERE c.snapshot_id = p_snapshot_id) INTO v_is_current;
  IF to_regclass('public.product_publication_member') IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM public.product_publication_member AS m WHERE m.snapshot_id = p_snapshot_id) INTO v_is_publication_member;
  END IF;

  IF COALESCE(v_is_sealed, false) OR COALESCE(v_is_current, false) OR COALESCE(v_is_publication_member, false) THEN
    SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_incoming
    FROM (SELECT ((x.member->>'kind') || '|' || (x.member->>'drill_key') || '|' || (x.member->>'tab') || '|' || (x.member->>'member_id') || '|' || ((x.member->>'position')) || '|' || ((x.member->'card')::text)) AS line FROM jsonb_array_elements(p_members) AS x(member)) AS m;
    SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_stored
    FROM (SELECT (y.kind || '|' || y.drill_key || '|' || y.tab || '|' || y.member_id || '|' || y.sort_position || '|' || y.card::text) AS line FROM public.product_overview_member AS y WHERE y.snapshot_id = p_snapshot_id) AS s;
    IF v_incoming IS NOT DISTINCT FROM v_stored THEN
      SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_incoming
      FROM (SELECT ((x.header->>'kind') || '|' || (x.header->>'drill_key') || '|' || (x.header->>'tab') || '|' || ((x.header->'header')::text)) AS line FROM jsonb_array_elements(p_headers) AS x(header)) AS h;
      SELECT md5(COALESCE(string_agg(line, ',' ORDER BY line), '')) INTO v_stored
      FROM (SELECT (y.kind || '|' || y.drill_key || '|' || y.tab || '|' || y.header::text) AS line FROM public.product_overview_drill AS y WHERE y.snapshot_id = p_snapshot_id) AS s;
    END IF;
    IF v_incoming IS NOT DISTINCT FROM v_stored THEN
      SELECT count(*) INTO v_members FROM public.product_overview_member WHERE snapshot_id = p_snapshot_id;
      SELECT count(*) INTO v_headers FROM public.product_overview_drill WHERE snapshot_id = p_snapshot_id;
      RETURN v_members + v_headers;
    END IF;
    RAISE EXCEPTION 'overview membership for published snapshot % is immutable; differing content requires a new candidate', p_snapshot_id;
  END IF;

  DELETE FROM public.product_overview_member AS m WHERE m.snapshot_id = p_snapshot_id;
  DELETE FROM public.product_overview_drill AS d WHERE d.snapshot_id = p_snapshot_id;

  INSERT INTO public.product_overview_member
      (snapshot_id, kind, drill_key, tab, member_id, sort_position, card)
  SELECT p_snapshot_id,
         m.member->>'kind', m.member->>'drill_key', m.member->>'tab', m.member->>'member_id',
         (m.member->>'position')::integer, m.member->'card'
  FROM jsonb_array_elements(p_members) WITH ORDINALITY AS m(member, ord);
  GET DIAGNOSTICS v_members = ROW_COUNT;

  INSERT INTO public.product_overview_drill
      (snapshot_id, kind, drill_key, tab, header)
  SELECT p_snapshot_id, h.header->>'kind', h.header->>'drill_key', h.header->>'tab', h.header->'header'
  FROM jsonb_array_elements(p_headers) WITH ORDINALITY AS h(header, ord);
  GET DIAGNOSTICS v_headers = ROW_COUNT;

  INSERT INTO public.product_overview_seal (snapshot_id) VALUES (p_snapshot_id) ON CONFLICT (snapshot_id) DO NOTHING;

  RETURN v_members + v_headers;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.stage_product_snapshot(p_kind text, p_scope_key text, p_payload jsonb, p_expected_sync_at text, p_expected_event_count bigint)
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.stage_product_snapshot_v2(
    p_kind, p_scope_key, p_payload,
    p_expected_sync_at, p_expected_event_count,
    NULL, NULL, NULL, NULL
  );
$function$
;

CREATE OR REPLACE FUNCTION public.stage_product_snapshot_v2(p_kind text, p_scope_key text, p_payload jsonb, p_expected_sync_at text, p_expected_event_count bigint, p_build_key text DEFAULT NULL::text, p_bounds_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_bounds_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_as_of_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id bigint;
  v_status text;
  v_sync_at timestamptz;
  v_event_count bigint;
BEGIN
  -- Safe retry: the same (kind, scope, build_key) reuses its staged row.
  -- The build_key encodes the source generation (watermark|event count), so
  -- reuse implies the same warehouse state; a newer sync gets a new key.
  IF p_build_key IS NOT NULL THEN
    SELECT s.id INTO v_id
    FROM public.product_snapshot AS s
    WHERE s.kind = p_kind
      AND s.scope_key = COALESCE(p_scope_key, '')
      AND s.build_key = p_build_key;
    IF FOUND THEN
      RETURN v_id;
    END IF;
  END IF;

  SELECT w.status, w.last_success_at INTO v_status, v_sync_at
  FROM public.export_watermarks AS w
  WHERE w.job_name = 'incremental';
  IF v_status IS DISTINCT FROM 'ok'
     OR v_sync_at::text IS DISTINCT FROM p_expected_sync_at
     OR p_expected_sync_at IS NULL THEN
    RAISE EXCEPTION 'warehouse sync changed during snapshot computation; keeping current';
  END IF;
  SELECT count(*) INTO v_event_count FROM public.events;
  IF v_event_count IS DISTINCT FROM p_expected_event_count
     OR p_expected_event_count IS NULL THEN
    RAISE EXCEPTION 'warehouse events changed during snapshot computation; keeping current';
  END IF;

  BEGIN
    INSERT INTO public.product_snapshot (
      kind, scope_key, payload,
      source_status, source_watermark_at, source_watermark_date,
      n_events, n_client, n_activation,
      build_key, bounds_from, bounds_to, as_of_at
    )
    VALUES (
      p_kind,
      COALESCE(p_scope_key, ''),
      p_payload,
      v_status,
      v_sync_at,
      (SELECT w.last_success_date FROM public.export_watermarks AS w
         WHERE w.job_name = 'incremental'),
      v_event_count,
      (SELECT count(*)::int FROM public.client_company),
      (SELECT count(*)::int FROM public.company_activation),
      p_build_key, p_bounds_from, p_bounds_to, p_as_of_at
    )
    RETURNING id INTO v_id;
    RETURN v_id;
  EXCEPTION WHEN unique_violation THEN
    -- A concurrent refresh staged the same build_key between our check and
    -- our insert. Reuse its row: same key means same generation, so sharing
    -- it is correct and prevents a duplicate candidate.
    IF p_build_key IS NOT NULL THEN
      SELECT s.id INTO v_id
      FROM public.product_snapshot AS s
      WHERE s.kind = p_kind
        AND s.scope_key = COALESCE(p_scope_key, '')
        AND s.build_key = p_build_key;
      IF FOUND THEN
        RETURN v_id;
      END IF;
    END IF;
    RAISE;
  END;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.stage_retention_period_drills(p_snapshot_id bigint, p_drills jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE s product_snapshot; digest text; old_digest text; cells jsonb; c jsonb; d jsonb; k text; tab text; expected integer:=0; n integer;
BEGIN
 PERFORM pg_advisory_xact_lock(p_snapshot_id);
 SELECT * INTO s FROM product_snapshot WHERE id=p_snapshot_id;
 IF NOT FOUND OR s.kind NOT IN ('retention-heatmap','retention-monthly','churn-trend') OR s.scope_key<>'' THEN RAISE EXCEPTION 'invalid retention period candidate'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(s.kind||'|'||s.scope_key));
 IF jsonb_typeof(p_drills) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'retention drills must be an object'; END IF;
 digest:=encode(sha256(convert_to(p_drills::text,'UTF8')),'hex');
 SELECT m.digest INTO old_digest FROM product_retention_period_seal m WHERE snapshot_id=p_snapshot_id;
 IF FOUND THEN
  IF old_digest=digest THEN RETURN; END IF;
  RAISE EXCEPTION 'sealed retention periods are immutable';
 END IF;
 IF EXISTS(SELECT 1 FROM product_snapshot_current WHERE snapshot_id=p_snapshot_id) OR EXISTS(SELECT 1 FROM product_publication_member WHERE snapshot_id=p_snapshot_id) THEN RAISE EXCEPTION 'cannot amend published retention snapshot'; END IF;
 cells:=CASE s.kind WHEN 'retention-heatmap' THEN s.payload->'value' WHEN 'retention-monthly' THEN s.payload->'value'->'cells' ELSE s.payload->'value'->'months' END;
 IF jsonb_typeof(cells) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'invalid retention card'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(cells) LOOP
  IF s.kind='churn-trend' THEN
   FOREACH tab IN ARRAY ARRAY['entered','churned','reactivated'] LOOP
    k:=(c->>'month')||':'||tab; d:=p_drills->k; expected:=expected+1;
    n:=(c->>CASE tab WHEN 'entered' THEN 'entered_churn' WHEN 'churned' THEN 'churned_companies' ELSE 'reactivated' END)::integer;
    IF d->>'month' IS DISTINCT FROM c->>'month' OR d->>'tab' IS DISTINCT FROM tab OR (d->>'total')::integer IS DISTINCT FROM n OR (d->>'expected_total')::integer IS DISTINCT FROM n OR
       d->'header'->'eligible_companies' IS DISTINCT FROM c->'eligible_companies' OR d->'header'->'churned_companies' IS DISTINCT FROM c->'churned_companies' OR jsonb_typeof(d->'users') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'churn card/drill mismatch'; END IF;
    IF n IS NULL OR n<0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(d->'users') u WHERE jsonb_typeof(u->'companies') IS DISTINCT FROM 'array') THEN RAISE EXCEPTION 'invalid churn population'; END IF;
    IF (SELECT count(*) FROM jsonb_array_elements(d->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') co) <> n OR
       (SELECT count(DISTINCT co->>'company_id') FROM jsonb_array_elements(d->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') co WHERE jsonb_typeof(co->'company_id')='string' AND co->>'company_id'<>'') <> n THEN RAISE EXCEPTION 'invalid churn membership'; END IF;
   END LOOP;
  ELSE
   k:=CASE s.kind WHEN 'retention-heatmap' THEN (c->>'cohort_week')||':'||(c->>'rel_week') ELSE (c->>'cohort_month')||':'||(c->>'rel_month') END;
   d:=p_drills->k; expected:=expected+1;
   IF d->>'cohort_week' IS DISTINCT FROM split_part(k,':',1) OR d->>'rel_week' IS DISTINCT FROM split_part(k,':',2) OR d->'cohort_size' IS DISTINCT FROM c->'cohort_size' OR d->'retained_company_count' IS DISTINCT FROM c->'retained_count' OR jsonb_typeof(d->'users') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'heatmap card/drill mismatch'; END IF;
  END IF;
 END LOOP;
 IF (SELECT count(*) FROM jsonb_object_keys(p_drills))<>expected THEN RAISE EXCEPTION 'retention drill manifest mismatch'; END IF;
 INSERT INTO product_retention_period_drill SELECT p_snapshot_id,key,value FROM jsonb_each(p_drills);
 INSERT INTO product_retention_period_seal VALUES(p_snapshot_id,digest);
END $function$
;

CREATE OR REPLACE FUNCTION public.stage_retention_summary_members(p_snapshot_id bigint, p_populations jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE s public.product_snapshot; d text; old_digest text; k text; p jsonb; n integer; expected integer; ids integer; total_ids integer; card jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(p_snapshot_id);
 SELECT * INTO s FROM public.product_snapshot WHERE id=p_snapshot_id;
 IF NOT FOUND OR s.kind <> 'retention-summary' OR s.scope_key <> '' THEN RAISE EXCEPTION 'invalid retention summary candidate'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(s.kind||'|'||s.scope_key));
 IF jsonb_typeof(p_populations) IS DISTINCT FROM 'object' OR
    (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_populations) x) IS DISTINCT FROM
    ARRAY['activation:activated','activation:not_activated','ttv:measured','ttv:unmeasured'] THEN
   RAISE EXCEPTION 'exactly four retention summary populations required';
 END IF;
 d:=encode(sha256(convert_to(p_populations::text,'UTF8')),'hex');
 SELECT digest INTO old_digest FROM public.product_retention_summary_seal WHERE snapshot_id=p_snapshot_id;
 IF FOUND THEN
   IF old_digest=d THEN RETURN; END IF;
   RAISE EXCEPTION 'sealed retention membership is immutable';
 END IF;
 IF EXISTS(SELECT 1 FROM product_snapshot_current WHERE snapshot_id=p_snapshot_id) OR
 EXISTS(SELECT 1 FROM product_publication_member WHERE snapshot_id=p_snapshot_id) THEN
   RAISE EXCEPTION 'cannot attach membership to an already published snapshot';
 END IF;
 card:=s.payload->'value';
 FOR k,p IN SELECT * FROM jsonb_each(p_populations) LOOP
   IF jsonb_typeof(p->'users') IS DISTINCT FROM 'array' OR p ? 'month_window' OR p->>'tab' IS DISTINCT FROM split_part(k,':',2) THEN RAISE EXCEPTION 'invalid retention population shape'; END IF;
   IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'users') u
     WHERE jsonb_typeof(u->'distinct_id') IS DISTINCT FROM 'string' OR u->>'distinct_id' = ''
       OR jsonb_typeof(u->'companies') IS DISTINCT FROM 'array') THEN
     RAISE EXCEPTION 'invalid retention user identity or companies';
   END IF;
   IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'users') u WHERE jsonb_array_length(u->'companies')=0) OR
      EXISTS (SELECT 1 FROM jsonb_array_elements(p->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') c
       WHERE jsonb_typeof(c->'company_id') IS DISTINCT FROM 'string' OR c->>'company_id'='') THEN
     RAISE EXCEPTION 'invalid retention company identity';
   END IF;
   n:=jsonb_array_length(p->'users');
   IF (p->>'user_total')::integer IS DISTINCT FROM n THEN RAISE EXCEPTION 'user count mismatch'; END IF;
   SELECT count(*),count(DISTINCT c->>'company_id') INTO total_ids,ids
   FROM jsonb_array_elements(p->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') c;
   expected:=CASE k WHEN 'activation:activated' THEN (card->>'activated')::integer
     WHEN 'activation:not_activated' THEN (card->>'client_companies')::integer-(card->>'activated')::integer
     WHEN 'ttv:measured' THEN (card->>'ttv_companies')::integer
     ELSE (card->>'activated')::integer-(card->>'ttv_companies')::integer END;
   IF expected IS NULL OR expected<0 OR ids IS DISTINCT FROM expected OR total_ids<>ids OR
    (p->>'company_total')::integer IS DISTINCT FROM expected OR (p->>'expected_company_total')::integer IS DISTINCT FROM expected OR
    p->'header'->'activated' IS DISTINCT FROM card->'activated' OR p->'header'->'client_companies' IS DISTINCT FROM card->'client_companies' THEN
    RAISE EXCEPTION 'retention card/member count mismatch'; END IF;
   IF k LIKE 'ttv:%' AND (p->'header'->'measured' IS DISTINCT FROM card->'ttv_companies' OR p->'header'->'average_ttv_hours' IS DISTINCT FROM card->'avg_ttv_hours') THEN RAISE EXCEPTION 'time to value card mismatch'; END IF;
 END LOOP;
 -- Exact company partitions, not merely equal sizes.
 IF EXISTS (
   SELECT c->>'company_id' FROM jsonb_array_elements(p_populations->'activation:activated'->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') c
   INTERSECT
   SELECT c->>'company_id' FROM jsonb_array_elements(p_populations->'activation:not_activated'->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') c
 ) THEN RAISE EXCEPTION 'activation tabs overlap'; END IF;
 IF EXISTS (
   WITH a AS (SELECT c->>'company_id' id FROM jsonb_array_elements(p_populations->'activation:activated'->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') c),
   t AS (SELECT c->>'company_id' id FROM jsonb_each(p_populations) x CROSS JOIN LATERAL jsonb_array_elements(x.value->'users') u CROSS JOIN LATERAL jsonb_array_elements(u->'companies') c WHERE x.key LIKE 'ttv:%')
   SELECT id FROM (SELECT id FROM a EXCEPT SELECT id FROM t) missing
   UNION ALL SELECT id FROM (SELECT id FROM t EXCEPT SELECT id FROM a) extra
   UNION ALL SELECT id FROM t GROUP BY id HAVING count(*)>1
 ) THEN RAISE EXCEPTION 'time to value partition mismatch'; END IF;
 FOR k,p IN SELECT * FROM jsonb_each(p_populations) LOOP
   INSERT INTO product_retention_summary_header VALUES(p_snapshot_id,k,p-'users');
   INSERT INTO product_retention_summary_member
   SELECT p_snapshot_id,k,(ord-1)::integer,u->>'distinct_id',u FROM jsonb_array_elements(p->'users') WITH ORDINALITY x(u,ord);
 END LOOP;
 INSERT INTO product_retention_summary_seal VALUES(p_snapshot_id,d);
END $function$
;

CREATE OR REPLACE FUNCTION public.try_begin_incremental(p_lease interval DEFAULT '00:15:00'::interval)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  claimed boolean;
BEGIN
  INSERT INTO public.export_watermarks (
    job_name, last_success_date, last_success_at, status, detail
  )
  VALUES ('incremental', NULL, now(), 'running', 'lease')
  ON CONFLICT (job_name) DO UPDATE
    SET status = 'running',
        last_success_at = now(),
        detail = 'lease'
  WHERE public.export_watermarks.status IS DISTINCT FROM 'running'
     OR public.export_watermarks.last_success_at IS NULL
     OR public.export_watermarks.last_success_at < now() - p_lease
  RETURNING true INTO claimed;
  RETURN COALESCE(claimed, false);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.upsert_mixpanel_events(p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  result record;
BEGIN
  SELECT *
  INTO result
  FROM public.upsert_mixpanel_events_detail(p_rows);
  RETURN result.inserted;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.upsert_mixpanel_events_detail(p_rows jsonb)
 RETURNS TABLE(inserted integer, updated integer, identity_mismatches integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  mismatch_count integer;
  inserted_count integer;
  updated_count integer;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'upsert_mixpanel_events expects a JSON array';
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS _property_incoming_v12 (
    insert_id text PRIMARY KEY,
    event_name text NOT NULL,
    event_time timestamptz NOT NULL,
    distinct_id text NOT NULL,
    user_id text,
    uc_uuid text,
    email text,
    company_id text,
    company text,
    properties jsonb NOT NULL,
    properties_contract text
  ) ON COMMIT DROP;
  TRUNCATE TABLE _property_incoming_v12;

  INSERT INTO _property_incoming_v12 (
    insert_id, event_name, event_time, distinct_id, user_id,
    uc_uuid, email, company_id, company, properties, properties_contract
  )
  SELECT DISTINCT ON (row_data.insert_id)
    row_data.insert_id,
    row_data.event_name,
    row_data.event_time,
    row_data.distinct_id,
    row_data.user_id,
    row_data.uc_uuid,
    row_data.email,
    row_data.company_id,
    row_data.company,
    public.normalize_event_properties(row_data.event_name, row_data.properties),
    row_data.properties_contract
  FROM (
    SELECT
      NULLIF(btrim(elem->>'insert_id'), '') AS insert_id,
      NULLIF(btrim(elem->>'event_name'), '') AS event_name,
      (elem->>'event_time')::timestamptz AS event_time,
      COALESCE(elem->>'distinct_id', '') AS distinct_id,
      NULLIF(elem->>'user_id', '') AS user_id,
      NULLIF(elem->>'uc_uuid', '') AS uc_uuid,
      NULLIF(elem->>'email', '') AS email,
      NULLIF(elem->>'company_id', '') AS company_id,
      NULLIF(elem->>'company', '') AS company,
      CASE
        WHEN jsonb_typeof(elem->'properties') = 'object'
          THEN elem->'properties'
        ELSE '{}'::jsonb
      END AS properties,
      CASE WHEN elem->>'properties_contract' = 'event_properties.v1.2'
        THEN 'event_properties.v1.2' ELSE NULL END AS properties_contract
    FROM jsonb_array_elements(p_rows) AS elem
  ) AS row_data
  WHERE row_data.insert_id IS NOT NULL
    AND row_data.event_name IS NOT NULL
    AND row_data.event_time IS NOT NULL
  ORDER BY row_data.insert_id, row_data.event_time DESC;

  SELECT count(*)::integer
  INTO mismatch_count
  FROM _property_incoming_v12 AS incoming
  JOIN public.events AS existing
    ON existing.insert_id = incoming.insert_id
  WHERE existing.event_name IS DISTINCT FROM incoming.event_name
     OR existing.event_time IS DISTINCT FROM incoming.event_time
     OR existing.distinct_id IS DISTINCT FROM incoming.distinct_id
     OR existing.company_id IS DISTINCT FROM incoming.company_id;

  IF mismatch_count > 10 THEN
    RAISE EXCEPTION 'identity mismatches exceed 10: %', mismatch_count;
  END IF;

  INSERT INTO public.events (
    insert_id, event_name, event_time, distinct_id, user_id,
    uc_uuid, email, company_id, company, properties, properties_contract
  )
  SELECT
    incoming.insert_id, incoming.event_name, incoming.event_time,
    incoming.distinct_id, incoming.user_id, incoming.uc_uuid,
    incoming.email, incoming.company_id, incoming.company,
    incoming.properties, incoming.properties_contract
  FROM _property_incoming_v12 AS incoming
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.events AS existing
    WHERE existing.insert_id = incoming.insert_id
  )
  ON CONFLICT (insert_id) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;

  UPDATE public.events AS existing
  SET properties = public.merge_event_properties(existing.properties, incoming.properties),
      properties_contract = COALESCE(incoming.properties_contract, existing.properties_contract)
  FROM _property_incoming_v12 AS incoming
  WHERE existing.insert_id = incoming.insert_id
    AND existing.event_name = incoming.event_name
    AND existing.event_time = incoming.event_time
    AND existing.distinct_id = incoming.distinct_id
    AND existing.company_id IS NOT DISTINCT FROM incoming.company_id
    AND (existing.properties IS DISTINCT FROM public.merge_event_properties(
      existing.properties, incoming.properties
    ) OR (incoming.properties_contract IS NOT NULL
      AND existing.properties_contract IS DISTINCT FROM incoming.properties_contract));
  GET DIAGNOSTICS updated_count = ROW_COUNT;

  RETURN QUERY SELECT inserted_count, updated_count, mismatch_count;
END;
$function$
;
