-- Harden the already-deployed private atomic page publisher without touching legacy.
-- Requires non-empty sealed memberships for each of the five Overview kinds.
-- Retention publication behavior remains unchanged.
CREATE OR REPLACE FUNCTION "01_product_schema".publish_product_publication(p_page text, p_source_watermark_at timestamp with time zone, p_n_events bigint, p_members jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO '01_product_schema', 'pg_catalog', 'pg_temp'
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
  PERFORM pg_advisory_xact_lock(hashtext('01_product_schema|' || 'page|' || p_page));
  FOR v_kind, v_scope IN
    SELECT DISTINCT u.kind, u.scope
    FROM unnest(v_kinds, v_scopes) AS u(kind, scope)
    ORDER BY 1, 2
  LOOP
    PERFORM pg_advisory_xact_lock(hashtext('01_product_schema|' || v_kind || '|' || v_scope));
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
    FROM "01_product_schema".product_snapshot AS s
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
  FROM "01_product_schema".product_publication AS p
  WHERE p.page = p_page
    AND p.source_watermark_at = p_source_watermark_at
    AND p.n_events = p_n_events;
  IF FOUND THEN
    SELECT COALESCE(array_agg(m.kind || '|' || m.scope_key || '|' || m.snapshot_id ORDER BY m.kind, m.scope_key), '{}')
      INTO v_existing_members
    FROM "01_product_schema".product_publication_member AS m
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
      FROM "01_product_schema".product_publication_current AS c
      WHERE c.page = p_page;
      IF v_has_current AND v_cur_pub_id = v_existing_id THEN
        RETURN v_existing_id;
      END IF;
      SELECT w.status, w.last_success_at INTO v_live_status, v_live_at
      FROM "01_product_schema".export_watermarks AS w
      WHERE w.job_name = 'incremental';
      SELECT count(*) INTO v_live_events FROM "01_product_schema".events;
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
        FROM "01_product_schema".product_publication_current AS c
        JOIN "01_product_schema".product_publication AS p ON p.publication_id = c.publication_id
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
        FROM "01_product_schema".product_publication_current AS c
        JOIN "01_product_schema".product_publication AS p ON p.publication_id = c.publication_id
        WHERE c.page = p_page;
        IF p_source_watermark_at < v_cur_at
           OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
          RETURN v_existing_id;
        END IF;
      END IF;
      INSERT INTO "01_product_schema".product_publication_current AS c
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
  FROM "01_product_schema".product_publication_current AS c
  JOIN "01_product_schema".product_publication AS p ON p.publication_id = c.publication_id
  WHERE c.page = p_page;
  IF v_has_current THEN
    IF p_source_watermark_at < v_cur_at
       OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
      RAISE EXCEPTION
        'publication generation (at %, events %) is older than current (at %, events %); keeping current',
        p_source_watermark_at, p_n_events, v_cur_at, v_cur_events;
    END IF;
  END IF;

  -- New fail-closed defense in depth: page publication itself must refuse
  -- unsealed or empty Overview members, even when called directly instead of
  -- via the five-kind coordinator. The retention page is unchanged.
  IF p_page = 'overview' THEN
    FOR v_idx IN 1 .. array_length(v_snap_ids,1) LOOP
      v_kind := v_kinds[v_idx];
      v_snapshot_id := v_snap_ids[v_idx];
      IF v_kind = 'overview-funnel' THEN
        IF NOT EXISTS (
          SELECT 1 FROM "01_product_schema".product_funnel_seal z
          WHERE z.snapshot_id=v_snapshot_id
        ) OR NOT EXISTS (
          SELECT 1 FROM "01_product_schema".product_funnel_member m
          WHERE m.snapshot_id=v_snapshot_id
        ) OR NOT EXISTS (
          SELECT 1 FROM "01_product_schema".product_funnel_drill d
          WHERE d.snapshot_id=v_snapshot_id
        ) THEN
          RAISE EXCEPTION 'overview funnel % not sealed with populated members and headers',v_snapshot_id;
        END IF;
      ELSE
        IF NOT EXISTS (
          SELECT 1 FROM "01_product_schema".product_overview_seal z
          WHERE z.snapshot_id=v_snapshot_id
        ) OR NOT EXISTS (
          SELECT 1 FROM "01_product_schema".product_overview_member m
          WHERE m.snapshot_id=v_snapshot_id
        ) OR NOT EXISTS (
          SELECT 1 FROM "01_product_schema".product_overview_drill d
          WHERE d.snapshot_id=v_snapshot_id
        ) THEN
          RAISE EXCEPTION 'overview kind % snapshot % not sealed with populated members and headers',
            v_kind,v_snapshot_id;
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- Candidate validation: every member must satisfy the same gates the
  -- per-kind path enforces (payload shape, completed sync, staged == live,
  -- coverage). A page can never publish what the per-kind path would refuse.
  FOR v_idx IN 1 .. array_length(v_snap_ids, 1) LOOP
    PERFORM "01_product_schema".assert_product_snapshot_publishable(v_snap_ids[v_idx]);
  END LOOP;

  -- Insert the manifest. A concurrent identical publisher wins the UNIQUE
  -- race here; ON CONFLICT DO NOTHING turns that into the idempotent path
  -- above instead of a generic unique-violation.
  INSERT INTO "01_product_schema".product_publication AS p
      (page, source_watermark_at, n_events)
  VALUES (p_page, p_source_watermark_at, p_n_events)
  ON CONFLICT (page, source_watermark_at, n_events) DO NOTHING
  RETURNING p.publication_id INTO v_publication_id;
  IF v_publication_id IS NULL THEN
    SELECT p.publication_id INTO v_existing_id
    FROM "01_product_schema".product_publication AS p
    WHERE p.page = p_page
      AND p.source_watermark_at = p_source_watermark_at
      AND p.n_events = p_n_events;
    SELECT COALESCE(array_agg(m.kind || '|' || m.scope_key || '|' || m.snapshot_id ORDER BY m.kind, m.scope_key), '{}')
      INTO v_existing_members
    FROM "01_product_schema".product_publication_member AS m
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
    INSERT INTO "01_product_schema".product_publication_member AS m
        (publication_id, kind, scope_key, snapshot_id)
    VALUES (v_publication_id, v_kinds[v_idx], v_scopes[v_idx], v_snap_ids[v_idx]);
  END LOOP;

  -- Revalidate before swapping: the warehouse may have advanced while this
  -- transaction validated members and inserted rows. The per-kind locks do
  -- not block the sync, so compare the single live generation once more;
  -- when it moved, the members just validated are stale and the swap must
  -- not happen. The previous publication keeps serving.
  SELECT w.status, w.last_success_at INTO v_live_status, v_live_at
  FROM "01_product_schema".export_watermarks AS w
  WHERE w.job_name = 'incremental';
  SELECT count(*) INTO v_live_events FROM "01_product_schema".events;
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
  FROM "01_product_schema".product_publication_current AS c
  JOIN "01_product_schema".product_publication AS p ON p.publication_id = c.publication_id
  WHERE c.page = p_page;
  IF v_has_current THEN
    IF p_source_watermark_at < v_cur_at
       OR (p_source_watermark_at = v_cur_at AND p_n_events < v_cur_events) THEN
      RAISE EXCEPTION
        'publication generation (at %, events %) is older than current (at %, events %); keeping current',
        p_source_watermark_at, p_n_events, v_cur_at, v_cur_events;
    END IF;
  END IF;

  INSERT INTO "01_product_schema".product_publication_current AS c
      (page, publication_id)
  VALUES (p_page, v_publication_id)
  ON CONFLICT (page) DO UPDATE
    SET publication_id = EXCLUDED.publication_id,
        swapped_at = now();
  RETURN v_publication_id;
END;
$function$
