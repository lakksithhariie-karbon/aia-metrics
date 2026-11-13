-- Exact original public Product writer/helper definitions. Restore part 4/5.
-- Retains existing function grants when run with CREATE OR REPLACE.
-- Review impact before applying. Captured 2026-11-07.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.refresh_overview_history_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '100s'
AS $function$
DECLARE
 v_wm timestamptz;v_latest timestamptz;v_month date;v_last date;
 v_cutoff timestamptz;v_snapshot_id bigint;v_members integer;v_count integer:=0;
 v_items jsonb:='[]'::jsonb;
BEGIN
 SELECT s.source_watermark_at,(s.payload#>>'{value,active_users,as_of}')::timestamptz
 INTO v_wm,v_latest
 FROM public.product_snapshot_current c JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1;
 IF v_wm IS NULL OR v_latest IS NULL THEN
  RAISE EXCEPTION 'Current verified Overview generation unavailable';
 END IF;
 FOR v_month IN
  SELECT generate_series(date '2026-03-01'::timestamp,
   (date_trunc('month',v_latest AT TIME ZONE 'Asia/Kolkata')-interval '1 month')::timestamp,
   interval '1 month')::date
 LOOP
  v_last:=(v_month+interval '1 month')::date-1;
  v_cutoff:=((v_last+1)::timestamp AT TIME ZONE 'Asia/Kolkata')-interval '1 second';

  SELECT id INTO v_snapshot_id FROM public.product_snapshot
  WHERE kind='overview' AND scope_key='asof='||to_char(v_last,'YYYY-MM-DD')
  ORDER BY created_at DESC LIMIT 1;
  IF v_snapshot_id IS NULL THEN
   INSERT INTO public.product_snapshot(
    kind,scope_key,payload,source_status,source_watermark_at,
    source_watermark_date,as_of_at,created_at,build_key
   ) VALUES(
    'overview','asof='||to_char(v_last,'YYYY-MM-DD'),
    jsonb_build_object('value',jsonb_build_object('active_users',
     jsonb_build_object('as_of',v_cutoff,'historical',true,'timezone','Asia/Kolkata'))),
    'ok',v_wm,(v_wm AT TIME ZONE 'Asia/Kolkata')::date,
    v_cutoff,now(),'verified-history-v1'
   ) RETURNING id INTO v_snapshot_id;
  ELSE
   UPDATE public.product_snapshot SET
    payload=jsonb_build_object('value',jsonb_build_object('active_users',
     jsonb_build_object('as_of',v_cutoff,'historical',true,'timezone','Asia/Kolkata'))),
    source_status='ok',source_watermark_at=v_wm,
    source_watermark_date=(v_wm AT TIME ZONE 'Asia/Kolkata')::date,
    as_of_at=v_cutoff,created_at=now(),build_key='verified-history-v1'
   WHERE id=v_snapshot_id;
  END IF;

  DELETE FROM public.product_overview_member WHERE snapshot_id=v_snapshot_id;

  WITH eligible AS MATERIALIZED(
   SELECT DISTINCT ON(e.company_id)
    e.company_id,e.event_time integrated_at,
    CASE lower(btrim(e.properties->>'type'))
      WHEN 'tally' THEN 'Tally' WHEN 'zoho' THEN 'Zoho Books'
      ELSE 'Unknown' END integration_type,
    coalesce(nullif(btrim(d.company_name),''),
      nullif(btrim(cp.company_name),''),e.company_id) company_name
   FROM public.events e
   JOIN public.client_company c ON c.company_id=e.company_id
   LEFT JOIN public.company_directory d ON d.company_uuid::text=e.company_id
   LEFT JOIN public.company_profile cp ON cp.company_id=e.company_id
   WHERE public.is_successful_integration(e.event_name,e.properties)
    AND e.event_time<v_cutoff-interval '28 days'
    AND e.ingested_at<=v_wm
    AND NOT coalesce(d.is_test,false)
   ORDER BY e.company_id,e.event_time,e.insert_id
  ),mature AS (
   SELECT * FROM eligible
   WHERE integrated_at>=v_cutoff-interval '56 days'
  ),ranked AS(
   SELECT *,row_number() OVER(ORDER BY integrated_at,company_id)-1 pos FROM mature
  )
  INSERT INTO public.product_overview_member(
    snapshot_id,kind,drill_key,tab,member_id,sort_position,card
  )
  SELECT v_snapshot_id,'overview',v.drill_key,'all',r.company_id,r.pos::integer,
   jsonb_build_object('company_name',r.company_name,
    'integration_type',r.integration_type,'integrated_at',r.integrated_at,
    'is_test',false,'historical',true)
  FROM ranked r CROSS JOIN (VALUES
    ('core_adoption_7d'),('sustained_adoption_28d'),('value_conversion_28d')
  ) v(drill_key);
  GET DIAGNOSTICS v_members=ROW_COUNT;
  v_count:=v_count+1;
  v_items:=v_items||jsonb_build_array(jsonb_build_object(
   'as_of',v_last,'snapshot_id',v_snapshot_id,
   'mature_integrations',v_members/3,'source_watermark_at',v_wm
  ));
 END LOOP;
 RETURN jsonb_build_object('built',v_count,'snapshots',v_items,'status','ok');
END;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_retention(p_source text DEFAULT 'public.events'::text)
 RETURNS TABLE(n_activation integer, n_week integer, n_cells integer, n_client integer, n_profile integer, n_week_action integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '145s'
AS $function$
DECLARE
  src text;
BEGIN
  IF p_source NOT IN ('public.events', 'metrics_scratch.events') THEN
    RAISE EXCEPTION 'refusing unsafe source table name: %', p_source;
  END IF;
  src := p_source;

  TRUNCATE TABLE
    public.client_company,
    public.company_activation,
    public.company_week_value,
    public.company_month_core,
    public.retention_cells,
    public.company_profile,
    public.company_week_action,
    public.company_core_activity;

  -- Client companies: unchanged staff/email contract from 002/003/004.
  EXECUTE format(
    $q$
    INSERT INTO public.client_company (company_id)
    SELECT company_id
    FROM %s
    WHERE company_id IS NOT NULL
    GROUP BY company_id
    HAVING COUNT(*) FILTER (
             WHERE email IS NOT NULL AND email <> ''
               AND NOT public.is_internal_email(email)
           ) > 0
        OR COUNT(*) FILTER (
             WHERE email IS NOT NULL AND email <> ''
           ) = 0
    $q$, src
  );

  -- Activation is outcome-based. The funnel columns are diagnostics only and
  -- never gate whether a company is activated.
  EXECUTE format(
    $q$
    WITH qual AS (
      SELECT s.company_id, s.event_time
      FROM %s AS s
      WHERE s.company_id IS NOT NULL
        AND public.is_qualifying_sync(s.event_name, s.properties)
        AND EXISTS (
          SELECT 1 FROM public.client_company AS c
          WHERE c.company_id = s.company_id
        )
    ), integ AS (
      SELECT s.company_id, MIN(s.event_time) AS integration_at
      FROM %s AS s
      WHERE s.company_id IS NOT NULL
        AND public.is_successful_integration(s.event_name, s.properties)
        AND EXISTS (
          SELECT 1 FROM public.client_company AS c
          WHERE c.company_id = s.company_id
        )
      GROUP BY s.company_id
    ), core_upload AS (
      SELECT
        s.company_id,
        MIN(s.event_time) AS module_upload_at,
        (array_agg(
           lower(btrim(COALESCE(s.properties->>'type', '')))
           ORDER BY s.event_time ASC, s.insert_id ASC
         ))[1] AS first_upload_type
      FROM %s AS s
      WHERE s.company_id IS NOT NULL
        AND s.event_name = 'Upload'
        AND lower(btrim(COALESCE(s.properties->>'type', '')))
            IN ('bill', 'invoice', 'statement')
        AND EXISTS (
          SELECT 1 FROM public.client_company AS c
          WHERE c.company_id = s.company_id
        )
      GROUP BY s.company_id
    ), ready AS (
      SELECT s.company_id, MIN(s.event_time) AS module_ready_at
      FROM %s AS s
      WHERE s.company_id IS NOT NULL
        AND (
          s.event_name = 'Invoice Created'
          OR (
            s.event_name = 'Transaction Ledger Updated'
            AND lower(btrim(COALESCE(s.properties->>'status', ''))) <> 'failed'
          )
        )
        AND EXISTS (
          SELECT 1 FROM public.client_company AS c
          WHERE c.company_id = s.company_id
        )
      GROUP BY s.company_id
    -- Second-day activation (2026-09-17 contract). The first qualifying sync
    -- only establishes the company's FIRST sync day (d1, IST calendar day) and
    -- is treated as training: it never activates. The company activates at its
    -- first qualifying sync on a STRICTLY LATER IST day, and a company with no
    -- such return produces no row here, so it gets no company_activation row.
    ), first_sync AS (
      SELECT q.company_id, MIN(q.event_time) AS activated_at
      FROM qual AS q
      JOIN (
        SELECT
          d.company_id,
          MIN((d.event_time AT TIME ZONE 'Asia/Kolkata')::date) AS first_sync_day
        FROM qual AS d
        GROUP BY d.company_id
      ) AS d1 ON d1.company_id = q.company_id
      WHERE (q.event_time AT TIME ZONE 'Asia/Kolkata')::date > d1.first_sync_day
      GROUP BY q.company_id
    ), ttv_sync AS (
      -- Time to Value uses the SAME reference sync as activation: the
      -- second-day sync. It is kept only when it is at/after the successful
      -- integration, so the LEFT JOIN below stores NULL for everything else
      -- (exactly the semantics the retention_kpis filter expects).
      SELECT fs.company_id, fs.activated_at AS ttv_sync_at
      FROM first_sync AS fs
      JOIN integ AS i ON i.company_id = fs.company_id
      WHERE fs.activated_at >= i.integration_at
    )
    INSERT INTO public.company_activation (
      company_id, activated_at, activation_week, activation_lane,
      integration_at, module_upload_at, module_ready_at, ttv_sync_at
    )
    SELECT
      fs.company_id,
      fs.activated_at,
      (date_trunc('week', fs.activated_at AT TIME ZONE 'Asia/Kolkata'))::date,
      CASE cu.first_upload_type
        WHEN 'bill' THEN 'ap'
        WHEN 'invoice' THEN 'ar'
        WHEN 'statement' THEN 'txn'
      END,
      i.integration_at,
      cu.module_upload_at,
      r.module_ready_at,
      t.ttv_sync_at
    FROM first_sync AS fs
    LEFT JOIN integ AS i ON i.company_id = fs.company_id
    LEFT JOIN core_upload AS cu ON cu.company_id = fs.company_id
    LEFT JOIN ready AS r ON r.company_id = fs.company_id
    LEFT JOIN ttv_sync AS t ON t.company_id = fs.company_id
    $q$, src, src, src, src
  );

  -- Core activity clock. Restricted to activated companies and to events at
  -- or after activation, matching the churn contract.
  EXECUTE format(
    $q$
    INSERT INTO public.company_core_activity (
      company_id, first_core_activity_at, last_core_activity_at,
      core_activity_count, core_active_weeks
    )
    SELECT
      s.company_id,
      MIN(s.event_time),
      MAX(s.event_time),
      COUNT(*)::int,
      COUNT(DISTINCT
        (date_trunc('week', s.event_time AT TIME ZONE 'Asia/Kolkata'))::date
      )::int
    FROM %s AS s
    JOIN public.company_activation AS a ON a.company_id = s.company_id
    WHERE s.company_id IS NOT NULL
      AND s.event_time >= a.activated_at
      AND public.is_core_activity(s.event_name, s.properties)
    GROUP BY s.company_id
    $q$, src
  );

  -- Week activity. had_value mirrors had_core for backward compatibility.
  EXECUTE format(
    $q$
    INSERT INTO public.company_week_value (
      company_id, week_start, had_value, had_core, had_sync, had_recon
    )
    SELECT
      s.company_id,
      (date_trunc('week', s.event_time AT TIME ZONE 'Asia/Kolkata'))::date
        AS week_start,
      BOOL_OR(public.is_core_activity(s.event_name, s.properties)) AS had_core,
      BOOL_OR(public.is_core_activity(s.event_name, s.properties)) AS had_value,
      BOOL_OR(s.event_name = 'Accounting Sync') AS had_sync,
      BOOL_OR(s.event_name = 'Recon Processed') AS had_recon
    FROM %s AS s
    WHERE s.company_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.client_company AS c
        WHERE c.company_id = s.company_id
      )
    GROUP BY s.company_id, week_start
    $q$, src
  );

  -- Month activity (2026-09-18 contract). The churn window is the IST calendar
  -- month, so the read model is one row per (company, month) that had core
  -- activity. Scoped to ACTIVATED companies and to events at/after activation,
  -- exactly like company_core_activity: a company cannot be "retained" in a
  -- month before it ever activated, and core activity before activation is not
  -- part of the contract.
  EXECUTE format(
    $q$
    INSERT INTO public.company_month_core (company_id, month_start, had_core)
    SELECT
      s.company_id,
      (date_trunc('month', s.event_time AT TIME ZONE 'Asia/Kolkata'))::date
        AS month_start,
      BOOL_OR(public.is_core_activity(s.event_name, s.properties)) AS had_core
    FROM %s AS s
    JOIN public.company_activation AS a ON a.company_id = s.company_id
    WHERE s.company_id IS NOT NULL
      AND s.event_time >= a.activated_at
      AND public.is_core_activity(s.event_name, s.properties)
    GROUP BY s.company_id, month_start
    $q$, src
  );

  -- Week-8 retention now reads CORE ACTIVITY, not value events.
  INSERT INTO public.retention_cells
      (cohort_week, rel_week, cohort_size, retained_count)
  SELECT
      a.activation_week AS cohort_week,
      g.rel_week AS rel_week,
      COUNT(*) AS cohort_size,
      COUNT(*) FILTER (WHERE w.had_core) AS retained_count
  FROM public.company_activation AS a
  CROSS JOIN generate_series(0, 8) AS g(rel_week)
  LEFT JOIN public.company_week_value AS w
    ON w.company_id = a.company_id
   AND w.week_start = a.activation_week + g.rel_week * 7
  GROUP BY a.activation_week, g.rel_week;

  EXECUTE format(
    $q$
    INSERT INTO public.company_profile (
        company_id, company_name, signed_up_at,
        activated_at, activation_week,
        first_upload_at, first_ready_at, first_sync_at,
        first_recon_at, last_action_at, action_count,
        active_weeks, path_had_upload, path_had_ready,
        path_had_sync, path_had_recon
    )
    SELECT
        a.company_id,
        nm.company_name,
        COALESCE(
            MIN(s.event_time) FILTER (
                WHERE s.event_name = 'Company Created'),
            MIN(s.event_time)
        ) AS signed_up_at,
        a.activated_at,
        a.activation_week,
        MIN(s.event_time) FILTER (
            WHERE s.event_name = 'Upload') AS first_upload_at,
        MIN(s.event_time) FILTER (
            WHERE s.event_name IN (
                'Invoice Created', 'Transaction Ledger Updated'
            )
        ) AS first_ready_at,
        MIN(s.event_time) FILTER (
            WHERE s.event_name = 'Accounting Sync'
        ) AS first_sync_at,
        MIN(s.event_time) FILTER (
            WHERE s.event_name = 'Recon Processed'
        ) AS first_recon_at,
        MAX(s.event_time) FILTER (
            WHERE s.event_name IN (
                'Upload', 'Mapping Completed', 'Saved Template Loaded',
                'Invoice Created', 'Invoice Bulk Edited', 'Download-Inv',
                'Preview', 'Transaction Ledger Updated', 'Transaction Status',
                'Transaction Type Updated',
                'Transaction Configuration Edited',
                'Vendor Mismatch Resolved', 'Accounting Sync',
                'Recon Processed', 'Entity Created', 'Delete',
                'Download', 'Export'
            )
        ) AS last_action_at,
        COUNT(*) FILTER (
            WHERE s.event_name IN (
                'Upload', 'Mapping Completed', 'Saved Template Loaded',
                'Invoice Created', 'Invoice Bulk Edited', 'Download-Inv',
                'Preview', 'Transaction Ledger Updated', 'Transaction Status',
                'Transaction Type Updated',
                'Transaction Configuration Edited',
                'Vendor Mismatch Resolved', 'Accounting Sync',
                'Recon Processed', 'Entity Created', 'Delete',
                'Download', 'Export'
            )
        )::int AS action_count,
        COUNT(DISTINCT
            (date_trunc('week', s.event_time AT TIME ZONE
             'Asia/Kolkata'))::date
        ) FILTER (
            WHERE s.event_name IN (
                'Upload', 'Mapping Completed', 'Saved Template Loaded',
                'Invoice Created', 'Invoice Bulk Edited', 'Download-Inv',
                'Preview', 'Transaction Ledger Updated', 'Transaction Status',
                'Transaction Type Updated',
                'Transaction Configuration Edited',
                'Vendor Mismatch Resolved', 'Accounting Sync',
                'Recon Processed', 'Entity Created', 'Delete',
                'Download', 'Export'
            )
        )::int AS active_weeks,
        COALESCE(BOOL_OR(
            s.event_name = 'Upload'), FALSE) AS path_had_upload,
        COALESCE(BOOL_OR(
            s.event_name IN (
                'Invoice Created', 'Transaction Ledger Updated'
            )
        ), FALSE) AS path_had_ready,
        COALESCE(BOOL_OR(
            s.event_name = 'Accounting Sync'),
            FALSE) AS path_had_sync,
        COALESCE(BOOL_OR(
            s.event_name = 'Recon Processed'),
            FALSE) AS path_had_recon
    FROM public.company_activation AS a
    JOIN %s AS s ON s.company_id = a.company_id
    LEFT JOIN (
        SELECT DISTINCT ON (company_id)
            company_id,
            NULLIF(properties->>'companyName', '') AS company_name
        FROM %s
        WHERE company_id IS NOT NULL
          AND NULLIF(properties->>'companyName', '') IS NOT NULL
        ORDER BY company_id, event_time DESC
    ) AS nm ON nm.company_id = a.company_id
    GROUP BY a.company_id, a.activated_at, a.activation_week,
        nm.company_name
    $q$, src, src
  );

  EXECUTE format(
    $q$
    INSERT INTO public.company_week_action (
        company_id, week_start, action_count, upload_count,
        txn_count, ap_count, sync_count, recon_count,
        other_action_count
    )
    SELECT
        s.company_id,
        (date_trunc('week', s.event_time AT TIME ZONE 'Asia/Kolkata'))::date
            AS week_start,
        COUNT(*)::int AS action_count,
        COUNT(*) FILTER (
            WHERE s.event_name = 'Upload')::int AS upload_count,
        COUNT(*) FILTER (
            WHERE s.event_name IN (
                'Transaction Ledger Updated',
                'Transaction Status',
                'Transaction Type Updated',
                'Transaction Configuration Edited',
                'Vendor Mismatch Resolved'
            )
        )::int AS txn_count,
        COUNT(*) FILTER (
            WHERE s.event_name IN (
                'Invoice Created',
                'Invoice Bulk Edited',
                'Download-Inv',
                'Preview'
            )
        )::int AS ap_count,
        COUNT(*) FILTER (
            WHERE s.event_name = 'Accounting Sync'
        )::int AS sync_count,
        COUNT(*) FILTER (
            WHERE s.event_name = 'Recon Processed'
        )::int AS recon_count,
        COUNT(*) FILTER (
            WHERE s.event_name IN (
                'Mapping Completed',
                'Saved Template Loaded',
                'Entity Created',
                'Delete',
                'Download',
                'Export'
            )
        )::int AS other_action_count
    FROM %s AS s
    WHERE s.company_id IS NOT NULL
      AND s.event_name IN (
          'Upload', 'Mapping Completed', 'Saved Template Loaded',
          'Invoice Created', 'Invoice Bulk Edited', 'Download-Inv',
          'Preview', 'Transaction Ledger Updated', 'Transaction Status',
          'Transaction Type Updated',
          'Transaction Configuration Edited',
          'Vendor Mismatch Resolved', 'Accounting Sync',
          'Recon Processed', 'Entity Created', 'Delete',
          'Download', 'Export'
      )
      AND EXISTS (
        SELECT 1 FROM public.client_company AS c
        WHERE c.company_id = s.company_id
      )
    GROUP BY s.company_id, week_start
    $q$, src
  );

  IF to_regprocedure('public.refresh_company_week_product(text)') IS NOT NULL THEN
    PERFORM public.refresh_company_week_product(src);
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*)::int FROM public.company_activation),
    (SELECT count(*)::int FROM public.company_week_value),
    (SELECT count(*)::int FROM public.retention_cells),
    (SELECT count(*)::int FROM public.client_company),
    (SELECT count(*)::int FROM public.company_profile),
    (SELECT count(*)::int FROM public.company_week_action);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_retention_dashboard_v3(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_source_watermark timestamptz;
  v_current_watermark timestamptz;
  v_activation_rows bigint;
  v_core_day_rows bigint;
begin
  -- Avoid concurrent pg_cron + ingest refresh TRUNCATE lock contention.
  if not pg_try_advisory_xact_lock(20261010, 3) then
    return jsonb_build_object('refreshed',false,'reason','refresh_already_running');
  end if;

  select w.last_success_at
    into v_source_watermark
  from public.export_watermarks w
  where w.job_name='incremental'
    and w.last_success_at is not null
    and (w.status='ok' or
      (w.status='failed' and w.detail like 'refresh_retention RPC failed:%'))
  order by w.last_success_at desc
  limit 1;

  select m.source_watermark_at
    into v_current_watermark
  from metrics_private.retention_dashboard_meta_v3 m
  where m.singleton=true;

  -- Never replace a valid cache watermark with NULL.
  if v_source_watermark is null then
    raise exception 'retention_source_watermark_unavailable';
  end if;

  if not coalesce(p_force,false)
     and v_source_watermark is not null
     and v_current_watermark is not null
     and v_source_watermark <= v_current_watermark then
    return jsonb_build_object(
      'refreshed',false,
      'source_watermark_at',v_current_watermark,
      'reason','source_unchanged'
    );
  end if;

  truncate table metrics_private.retention_activation_v3;

  insert into metrics_private.retention_activation_v3 (
    company_id,
    integration_at,
    integration_month,
    training_sync_at,
    post_training_core_at,
    activated_at
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    where public.is_successful_integration(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.company_id,e.event_time asc,e.insert_id asc
  )
  select
    i.company_id,
    i.integration_at,
    date_trunc('month',i.integration_at at time zone 'Asia/Kolkata')::date,
    training.training_sync_at,
    core.post_training_core_at,
    activation.activated_at
  from first_integration i
  left join lateral (
    select e.event_time as training_sync_at
    from public.events e
    where e.company_id=i.company_id
      and e.event_time>=i.integration_at
      and public.is_qualifying_sync(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) training on true
  left join lateral (
    select e.event_time as post_training_core_at
    from public.events e
    where e.company_id=i.company_id
      and training.training_sync_at is not null
      and (e.event_time at time zone 'Asia/Kolkata')::date
          > (training.training_sync_at at time zone 'Asia/Kolkata')::date
      and public.is_core_activity(e.event_name,e.properties)
      and e.event_name<>'Accounting Sync'
      and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) core on true
  left join lateral (
    select e.event_time as activated_at
    from public.events e
    where e.company_id=i.company_id
      and core.post_training_core_at is not null
      and e.event_time>core.post_training_core_at
      and public.is_qualifying_sync(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) activation on true;

  get diagnostics v_activation_rows = row_count;

  truncate table metrics_private.retention_core_day_v3;

  insert into metrics_private.retention_core_day_v3 (
    company_id,
    activity_date
  )
  select
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date
  from public.events e
  join metrics_private.retention_activation_v3 a
    on a.company_id=e.company_id
   and a.activated_at is not null
  where e.event_time>=a.activated_at
    and public.is_core_activity(e.event_name,e.properties)
    and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date;

  get diagnostics v_core_day_rows = row_count;

  insert into metrics_private.retention_dashboard_meta_v3 (
    singleton,source_watermark_at,refreshed_at
  )
  values (
    true,
    v_source_watermark,
    now()
  )
  on conflict (singleton) do update
    set source_watermark_at=excluded.source_watermark_at,
        refreshed_at=excluded.refreshed_at;

  return jsonb_build_object(
    'refreshed',true,
    'activation_rows',v_activation_rows,
    'core_day_rows',v_core_day_rows,
    'source_watermark_at',v_source_watermark,
    'refreshed_at',now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_retention_dashboard_v4(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_source_watermark timestamptz;
  v_current_watermark timestamptz;
  v_activation_rows bigint;
  v_core_day_rows bigint;
begin
  -- Avoid concurrent pg_cron + ingest refresh TRUNCATE lock contention.
  if not pg_try_advisory_xact_lock(20261010, 4) then
    return jsonb_build_object('refreshed',false,'reason','refresh_already_running');
  end if;

  select w.last_success_at
    into v_source_watermark
  from public.export_watermarks w
  where w.job_name='incremental'
    and w.last_success_at is not null
    and (w.status='ok' or
      (w.status='failed' and w.detail like 'refresh_retention RPC failed:%'))
  order by w.last_success_at desc
  limit 1;

  select m.source_watermark_at
    into v_current_watermark
  from metrics_private.retention_dashboard_meta_v4 m
  where m.singleton=true;

  -- Never replace a valid cache watermark with NULL.
  if v_source_watermark is null then
    raise exception 'retention_source_watermark_unavailable';
  end if;

  if not coalesce(p_force,false)
     and v_source_watermark is not null
     and v_current_watermark is not null
     and v_source_watermark <= v_current_watermark then
    return jsonb_build_object(
      'refreshed',false,
      'source_watermark_at',v_current_watermark,
      'reason','source_unchanged'
    );
  end if;

  truncate table metrics_private.retention_activation_v4;

  insert into metrics_private.retention_activation_v4 (
    company_id,
    integration_at,
    integration_month,
    training_sync_at,
    post_training_core_at,
    activated_at
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    left join public.company_directory d on d.company_uuid::text=e.company_id
    where public.is_successful_integration(e.event_name,e.properties)
      and not coalesce(d.is_test,false)
    order by e.company_id,e.event_time asc,e.insert_id asc
  )
  select
    i.company_id,
    i.integration_at,
    date_trunc('month',i.integration_at at time zone 'Asia/Kolkata')::date,
    training.training_sync_at,
    core.post_training_core_at,
    activation.activated_at
  from first_integration i
  left join lateral (
    select e.event_time as training_sync_at
    from public.events e
    where e.company_id=i.company_id
      and e.event_time>=i.integration_at
      and public.is_qualifying_sync(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) training on true
  left join lateral (
    select e.event_time as post_training_core_at
    from public.events e
    where e.company_id=i.company_id
      and training.training_sync_at is not null
      and (e.event_time at time zone 'Asia/Kolkata')::date
          > (training.training_sync_at at time zone 'Asia/Kolkata')::date
      and public.is_core_activity(e.event_name,e.properties)
      and e.event_name<>'Accounting Sync'
      and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) core on true
  left join lateral (
    select e.event_time as activated_at
    from public.events e
    where e.company_id=i.company_id
      and core.post_training_core_at is not null
      and e.event_time>core.post_training_core_at
      and public.is_qualifying_sync(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) activation on true;

  get diagnostics v_activation_rows = row_count;

  truncate table metrics_private.retention_core_day_v4;

  insert into metrics_private.retention_core_day_v4 (
    company_id,
    activity_date
  )
  select
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date
  from public.events e
  join metrics_private.retention_activation_v4 a
    on a.company_id=e.company_id
   and a.activated_at is not null
  where e.event_time>=a.activated_at
    and e.event_name<>'Accounting Sync'
    and public.is_core_activity(e.event_name,e.properties)
    and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date;

  get diagnostics v_core_day_rows = row_count;

  insert into metrics_private.retention_dashboard_meta_v4 (
    singleton,source_watermark_at,refreshed_at
  )
  values (
    true,
    v_source_watermark,
    now()
  )
  on conflict (singleton) do update
    set source_watermark_at=excluded.source_watermark_at,
        refreshed_at=excluded.refreshed_at;

  return jsonb_build_object(
    'refreshed',true,
    'activation_rows',v_activation_rows,
    'core_day_rows',v_core_day_rows,
    'source_watermark_at',v_source_watermark,
    'refreshed_at',now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_retention_heatmap_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
declare
  v_rows bigint;
begin
  truncate table metrics_private.retention_week_core_v2;

  insert into metrics_private.retention_week_core_v2 (
    company_id,
    week_start
  )
  select
    e.company_id,
    date_trunc(
      'week',
      e.event_time at time zone 'Asia/Kolkata'
    )::date
  from public.events e
  join metrics_private.retention_activation_v2 a
    on a.company_id=e.company_id
   and a.activated_at is not null
  where e.event_time>=a.activated_at
    and public.is_core_activity(e.event_name,e.properties)
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    date_trunc(
      'week',
      e.event_time at time zone 'Asia/Kolkata'
    )::date;

  get diagnostics v_rows = row_count;

  return jsonb_build_object(
    'week_core_rows',v_rows,
    'refreshed_at',now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_retention_kpis_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_integrated bigint;
  v_activated bigint;
  v_month_rows bigint;
  v_watermark timestamptz;
begin
  truncate table metrics_private.retention_activation_v2;

  insert into metrics_private.retention_activation_v2 (
    company_id,
    integration_at,
    integration_month,
    training_sync_at,
    post_training_core_at,
    activated_at
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where public.is_successful_integration(e.event_name, e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.company_id, e.event_time asc, e.insert_id asc
  )
  select
    i.company_id,
    i.integration_at,
    date_trunc('month', i.integration_at at time zone 'Asia/Kolkata')::date,
    training.training_sync_at,
    core.post_training_core_at,
    activation.activated_at
  from first_integration i
  left join lateral (
    select e.event_time as training_sync_at
    from public.events e
    where e.company_id = i.company_id
      and e.event_time >= i.integration_at
      and public.is_qualifying_sync(e.event_name, e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc, e.insert_id asc
    limit 1
  ) training on true
  left join lateral (
    select e.event_time as post_training_core_at
    from public.events e
    where e.company_id = i.company_id
      and training.training_sync_at is not null
      and (e.event_time at time zone 'Asia/Kolkata')::date
          > (training.training_sync_at at time zone 'Asia/Kolkata')::date
      and public.is_core_activity(e.event_name, e.properties)
      and e.event_name <> 'Accounting Sync'
      and lower(btrim(coalesce(e.properties->>'status', ''))) <> 'failed'
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc, e.insert_id asc
    limit 1
  ) core on true
  left join lateral (
    select e.event_time as activated_at
    from public.events e
    where e.company_id = i.company_id
      and core.post_training_core_at is not null
      and e.event_time > core.post_training_core_at
      and public.is_qualifying_sync(e.event_name, e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc, e.insert_id asc
    limit 1
  ) activation on true;

  get diagnostics v_integrated = row_count;

  select count(*) into v_activated
  from metrics_private.retention_activation_v2
  where activated_at is not null;

  truncate table metrics_private.retention_month_core_v2;

  insert into metrics_private.retention_month_core_v2 (company_id, month_start)
  select
    e.company_id,
    date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date
  from public.events e
  join metrics_private.retention_activation_v2 a
    on a.company_id = e.company_id
   and a.activated_at is not null
  where e.event_time >= a.activated_at
    and public.is_core_activity(e.event_name, e.properties)
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date;

  get diagnostics v_month_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name = 'incremental' and w.status = 'ok'
  order by w.last_success_at desc
  limit 1;

  insert into metrics_private.retention_kpi_meta_v2 (
    singleton, source_watermark_at, refreshed_at
  )
  values (true, v_watermark, now())
  on conflict (singleton) do update
    set source_watermark_at = excluded.source_watermark_at,
        refreshed_at = excluded.refreshed_at;

  return jsonb_build_object(
    'integrated_companies', v_integrated,
    'activated_companies', v_activated,
    'month_core_rows', v_month_rows,
    'source_watermark_at', v_watermark,
    'refreshed_at', now()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.release_retention_period_build(p_kind text, p_token uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 DELETE FROM product_retention_build_lease WHERE kind=p_kind AND token=p_token;
$function$
;

CREATE OR REPLACE FUNCTION public.retention_period_is_sealed(p_snapshot_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT EXISTS(SELECT 1 FROM product_retention_period_seal WHERE snapshot_id=p_snapshot_id) $function$
;

CREATE OR REPLACE FUNCTION public.retention_summary_is_sealed(p_snapshot_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 SELECT EXISTS(SELECT 1 FROM product_retention_summary_seal WHERE snapshot_id=p_snapshot_id);
$function$
;
