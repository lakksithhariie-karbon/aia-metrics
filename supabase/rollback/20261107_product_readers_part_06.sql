-- Exact original public Product read RPCs, part 6/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_overview_core_users_v1(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '25s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id AS snapshot_id,
         (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
         s.source_watermark_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
    AND c.snapshot_id=p_snapshot_id
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.company_id, e.email, e.company, e.event_time,
         (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
         CASE
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill'
             OR e.event_name='Vendor Mismatch Resolved'
             THEN 'ap'
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice'
             OR e.event_name='Invoice Bulk Edited'
             THEN 'ar'
           ELSE 'transactions'
         END AS module
  FROM public.events e CROSS JOIN published p
  WHERE e.event_time >= p.as_of_at - interval '30 days'
    AND e.event_time < p.as_of_at
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
    AND e.company_id IS NOT NULL AND e.company_id <> ''
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name,e.properties)
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
pairs AS MATERIALIZED (
  SELECT q.distinct_id, q.company_id, max(nullif(q.email,'')) AS email,
         max(nullif(q.company,'')) AS event_company_name,
         count(*)::integer AS actions_30,
         count(*) FILTER(WHERE q.event_time >= p.as_of_at-interval '7 days')::integer AS actions_7,
         count(DISTINCT q.activity_day)::integer AS active_days_30,
         count(DISTINCT q.activity_day) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days')::integer AS active_days_7,
         max(q.event_time) AS last_30,
         max(q.event_time) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days') AS last_7,
         count(*) FILTER(WHERE q.module='ap')::integer AS ap_30,
         count(*) FILTER(WHERE q.module='ar')::integer AS ar_30,
         count(*) FILTER(WHERE q.module='transactions')::integer AS transactions_30,
         count(*) FILTER(WHERE q.module='ap' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ap_7,
         count(*) FILTER(WHERE q.module='ar' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ar_7,
         count(*) FILTER(WHERE q.module='transactions' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS transactions_7
  FROM qualified q CROSS JOIN published p
  GROUP BY q.distinct_id,q.company_id
),
named_pairs AS MATERIALIZED (
  SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
      a.event_company_name,a.company_id) AS company_name,
      coalesce(d.is_test,false) AS is_test
  FROM pairs a
  LEFT JOIN public.company_directory d ON d.company_uuid::text=a.company_id
  LEFT JOIN public.company_profile cp ON cp.company_id=a.company_id
),
users AS MATERIALIZED (
  SELECT a.distinct_id AS id,max(a.email) AS email,
         sum(a.actions_30)::integer AS actions_30,
         sum(a.actions_7)::integer AS actions_7,
         sum(a.ap_30)::integer AS ap_30, sum(a.ar_30)::integer AS ar_30,
         sum(a.transactions_30)::integer AS transactions_30,
         sum(a.ap_7)::integer AS ap_7, sum(a.ar_7)::integer AS ar_7,
         sum(a.transactions_7)::integer AS transactions_7,
         max(a.last_30) AS last_30, max(a.last_7) AS last_7
  FROM named_pairs a GROUP BY a.distinct_id
),
user_days AS (
  SELECT q.distinct_id AS id,count(DISTINCT q.activity_day)::integer AS days_30,
         count(DISTINCT q.activity_day) FILTER(
           WHERE q.event_time>=p.as_of_at-interval '7 days'
         )::integer AS days_7
  FROM qualified q CROSS JOIN published p GROUP BY q.distinct_id
),
classified AS MATERIALIZED (
  SELECT u.*,d.days_30,d.days_7,
         CASE WHEN p_segment='wau' THEN u.actions_7>0
              WHEN p_segment='mau_only' THEN u.actions_7=0
              ELSE u.actions_30>0 END AS included
  FROM users u JOIN user_days d USING(id)
),
matched AS (
  SELECT u.*
  FROM classified u
  WHERE u.included
    AND (
      coalesce(btrim(p_query),'')=''
      OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
      OR EXISTS(
        SELECT 1 FROM named_pairs a WHERE a.distinct_id=u.id
        AND (p_segment<>'wau' OR a.actions_7>0)
        AND a.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
      )
    )
    AND (
      p_module NOT IN ('ap','ar','transactions')
      OR (p_module='ap' AND
          CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END >0)
      OR (p_module='ar' AND
          CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END >0)
      OR (p_module='transactions' AND
          CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END >0)
    )
),
page_rows AS (
  SELECT u.* FROM matched u
  ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST, u.id
  LIMIT greatest(1,least(coalesce(p_page_size,10),25))
  OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
  'snapshot_id',p.snapshot_id,
  'segment',p_segment,
  'as_of',p.as_of_at,
  'source_watermark_at',p.source_watermark_at,
  'total',(SELECT count(*) FROM matched),
  'segment_total',(SELECT count(*) FROM classified WHERE included),
  'page',greatest(coalesce(p_page,1),1),
  'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
  'rows',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',u.id,
      'email',coalesce(u.email,u.id),
      'actions',CASE WHEN p_segment='wau' THEN u.actions_7 ELSE u.actions_30 END,
      'active_days',CASE WHEN p_segment='wau' THEN u.days_7 ELSE u.days_30 END,
      'last_active_at',CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END,
      'modules',jsonb_build_object(
        'ap',CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END,
        'ar',CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END,
        'transactions',CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END
      ),
      'companies',coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id',a.company_id, 'name',a.company_name,'is_test',a.is_test,
          'actions',CASE WHEN p_segment='wau' THEN a.actions_7 ELSE a.actions_30 END,
          'active_days',CASE WHEN p_segment='wau' THEN a.active_days_7 ELSE a.active_days_30 END,
          'last_active_at',CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END,
          'modules',jsonb_build_object(
            'ap',CASE WHEN p_segment='wau' THEN a.ap_7 ELSE a.ap_30 END,
            'ar',CASE WHEN p_segment='wau' THEN a.ar_7 ELSE a.ar_30 END,
            'transactions',CASE WHEN p_segment='wau' THEN a.transactions_7 ELSE a.transactions_30 END
          )
        ) ORDER BY
          (CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END) DESC NULLS LAST,a.company_id)
        FROM named_pairs a
        WHERE a.distinct_id=u.id AND (p_segment<>'wau' OR a.actions_7>0)
      ),'[]'::jsonb)
    ) ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST,u.id)
    FROM page_rows u
  ),'[]'::jsonb)
)
FROM published p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_core_users_v2(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '25s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id AS snapshot_id,
         (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
         s.source_watermark_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
    AND c.snapshot_id=p_snapshot_id
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.company_id, e.email, e.company, e.event_time,
         (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
         CASE
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill'
             OR e.event_name='Vendor Mismatch Resolved'
             THEN 'ap'
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice'
             OR e.event_name='Invoice Bulk Edited'
             THEN 'ar'
           ELSE 'transactions'
         END AS module
  FROM metrics_private.events_no_test_v2 e CROSS JOIN published p
  WHERE e.event_time >= p.as_of_at - interval '30 days'
    AND e.event_time < p.as_of_at
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
    AND e.company_id IS NOT NULL AND e.company_id <> ''
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name,e.properties)
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
pairs AS MATERIALIZED (
  SELECT q.distinct_id, q.company_id, max(nullif(q.email,'')) AS email,
         max(nullif(q.company,'')) AS event_company_name,
         count(*)::integer AS actions_30,
         count(*) FILTER(WHERE q.event_time >= p.as_of_at-interval '7 days')::integer AS actions_7,
         count(DISTINCT q.activity_day)::integer AS active_days_30,
         count(DISTINCT q.activity_day) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days')::integer AS active_days_7,
         max(q.event_time) AS last_30,
         max(q.event_time) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days') AS last_7,
         count(*) FILTER(WHERE q.module='ap')::integer AS ap_30,
         count(*) FILTER(WHERE q.module='ar')::integer AS ar_30,
         count(*) FILTER(WHERE q.module='transactions')::integer AS transactions_30,
         count(*) FILTER(WHERE q.module='ap' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ap_7,
         count(*) FILTER(WHERE q.module='ar' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ar_7,
         count(*) FILTER(WHERE q.module='transactions' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS transactions_7
  FROM qualified q CROSS JOIN published p
  GROUP BY q.distinct_id,q.company_id
),
named_pairs AS MATERIALIZED (
  SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
      a.event_company_name,a.company_id) AS company_name,
      coalesce(d.is_test,false) AS is_test
  FROM pairs a
  LEFT JOIN public.company_directory d ON d.company_uuid::text=a.company_id
  LEFT JOIN public.company_profile cp ON cp.company_id=a.company_id
),
users AS MATERIALIZED (
  SELECT a.distinct_id AS id,max(a.email) AS email,
         sum(a.actions_30)::integer AS actions_30,
         sum(a.actions_7)::integer AS actions_7,
         sum(a.ap_30)::integer AS ap_30, sum(a.ar_30)::integer AS ar_30,
         sum(a.transactions_30)::integer AS transactions_30,
         sum(a.ap_7)::integer AS ap_7, sum(a.ar_7)::integer AS ar_7,
         sum(a.transactions_7)::integer AS transactions_7,
         max(a.last_30) AS last_30, max(a.last_7) AS last_7
  FROM named_pairs a GROUP BY a.distinct_id
),
user_days AS (
  SELECT q.distinct_id AS id,count(DISTINCT q.activity_day)::integer AS days_30,
         count(DISTINCT q.activity_day) FILTER(
           WHERE q.event_time>=p.as_of_at-interval '7 days'
         )::integer AS days_7
  FROM qualified q CROSS JOIN published p GROUP BY q.distinct_id
),
classified AS MATERIALIZED (
  SELECT u.*,d.days_30,d.days_7,
         CASE WHEN p_segment='wau' THEN u.actions_7>0
              WHEN p_segment='mau_only' THEN u.actions_7=0
              ELSE u.actions_30>0 END AS included
  FROM users u JOIN user_days d USING(id)
),
matched AS (
  SELECT u.*
  FROM classified u
  WHERE u.included
    AND (
      coalesce(btrim(p_query),'')=''
      OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
      OR EXISTS(
        SELECT 1 FROM named_pairs a WHERE a.distinct_id=u.id
        AND (p_segment<>'wau' OR a.actions_7>0)
        AND a.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
      )
    )
    AND (
      p_module NOT IN ('ap','ar','transactions')
      OR (p_module='ap' AND
          CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END >0)
      OR (p_module='ar' AND
          CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END >0)
      OR (p_module='transactions' AND
          CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END >0)
    )
),
page_rows AS (
  SELECT u.* FROM matched u
  ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST, u.id
  LIMIT greatest(1,least(coalesce(p_page_size,10),25))
  OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
  'snapshot_id',p.snapshot_id,
  'segment',p_segment,
  'as_of',p.as_of_at,
  'source_watermark_at',p.source_watermark_at,
  'total',(SELECT count(*) FROM matched),
  'segment_total',(SELECT count(*) FROM classified WHERE included),
  'page',greatest(coalesce(p_page,1),1),
  'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
  'rows',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',u.id,
      'email',coalesce(u.email,u.id),
      'actions',CASE WHEN p_segment='wau' THEN u.actions_7 ELSE u.actions_30 END,
      'active_days',CASE WHEN p_segment='wau' THEN u.days_7 ELSE u.days_30 END,
      'last_active_at',CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END,
      'modules',jsonb_build_object(
        'ap',CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END,
        'ar',CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END,
        'transactions',CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END
      ),
      'companies',coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id',a.company_id, 'name',a.company_name,'is_test',a.is_test,
          'actions',CASE WHEN p_segment='wau' THEN a.actions_7 ELSE a.actions_30 END,
          'active_days',CASE WHEN p_segment='wau' THEN a.active_days_7 ELSE a.active_days_30 END,
          'last_active_at',CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END,
          'modules',jsonb_build_object(
            'ap',CASE WHEN p_segment='wau' THEN a.ap_7 ELSE a.ap_30 END,
            'ar',CASE WHEN p_segment='wau' THEN a.ar_7 ELSE a.ar_30 END,
            'transactions',CASE WHEN p_segment='wau' THEN a.transactions_7 ELSE a.transactions_30 END
          )
        ) ORDER BY
          (CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END) DESC NULLS LAST,a.company_id)
        FROM named_pairs a
        WHERE a.distinct_id=u.id AND (p_segment<>'wau' OR a.actions_7>0)
      ),'[]'::jsonb)
    ) ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST,u.id)
    FROM page_rows u
  ),'[]'::jsonb)
)
FROM published p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_core_users_v3(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '25s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id AS snapshot_id,
         (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
         s.source_watermark_at
  FROM public.product_snapshot s
  WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
    AND s.id=p_snapshot_id
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.company_id, e.email, e.company, e.event_time,
         (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
         CASE
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill'
             OR e.event_name='Vendor Mismatch Resolved'
             THEN 'ap'
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice'
             OR e.event_name='Invoice Bulk Edited'
             THEN 'ar'
           ELSE 'transactions'
         END AS module
  FROM metrics_private.events_no_test_v2 e CROSS JOIN published p
  WHERE e.event_time >= p.as_of_at - interval '30 days'
    AND e.event_time < p.as_of_at
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
    AND e.company_id IS NOT NULL AND e.company_id <> ''
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name,e.properties)
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
pairs AS MATERIALIZED (
  SELECT q.distinct_id, q.company_id, max(nullif(q.email,'')) AS email,
         max(nullif(q.company,'')) AS event_company_name,
         count(*)::integer AS actions_30,
         count(*) FILTER(WHERE q.event_time >= p.as_of_at-interval '7 days')::integer AS actions_7,
         count(DISTINCT q.activity_day)::integer AS active_days_30,
         count(DISTINCT q.activity_day) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days')::integer AS active_days_7,
         max(q.event_time) AS last_30,
         max(q.event_time) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days') AS last_7,
         count(*) FILTER(WHERE q.module='ap')::integer AS ap_30,
         count(*) FILTER(WHERE q.module='ar')::integer AS ar_30,
         count(*) FILTER(WHERE q.module='transactions')::integer AS transactions_30,
         count(*) FILTER(WHERE q.module='ap' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ap_7,
         count(*) FILTER(WHERE q.module='ar' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ar_7,
         count(*) FILTER(WHERE q.module='transactions' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS transactions_7
  FROM qualified q CROSS JOIN published p
  GROUP BY q.distinct_id,q.company_id
),
named_pairs AS MATERIALIZED (
  SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
      a.event_company_name,a.company_id) AS company_name,
      coalesce(d.is_test,false) AS is_test
  FROM pairs a
  LEFT JOIN public.company_directory d ON d.company_uuid::text=a.company_id
  LEFT JOIN public.company_profile cp ON cp.company_id=a.company_id
),
users AS MATERIALIZED (
  SELECT a.distinct_id AS id,max(a.email) AS email,
         sum(a.actions_30)::integer AS actions_30,
         sum(a.actions_7)::integer AS actions_7,
         sum(a.ap_30)::integer AS ap_30, sum(a.ar_30)::integer AS ar_30,
         sum(a.transactions_30)::integer AS transactions_30,
         sum(a.ap_7)::integer AS ap_7, sum(a.ar_7)::integer AS ar_7,
         sum(a.transactions_7)::integer AS transactions_7,
         max(a.last_30) AS last_30, max(a.last_7) AS last_7
  FROM named_pairs a GROUP BY a.distinct_id
),
user_days AS (
  SELECT q.distinct_id AS id,count(DISTINCT q.activity_day)::integer AS days_30,
         count(DISTINCT q.activity_day) FILTER(
           WHERE q.event_time>=p.as_of_at-interval '7 days'
         )::integer AS days_7
  FROM qualified q CROSS JOIN published p GROUP BY q.distinct_id
),
classified AS MATERIALIZED (
  SELECT u.*,d.days_30,d.days_7,
         CASE WHEN p_segment='wau' THEN u.actions_7>0
              WHEN p_segment='mau_only' THEN u.actions_7=0
              ELSE u.actions_30>0 END AS included
  FROM users u JOIN user_days d USING(id)
),
matched AS (
  SELECT u.*
  FROM classified u
  WHERE u.included
    AND (
      coalesce(btrim(p_query),'')=''
      OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
      OR EXISTS(
        SELECT 1 FROM named_pairs a WHERE a.distinct_id=u.id
        AND (p_segment<>'wau' OR a.actions_7>0)
        AND a.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
      )
    )
    AND (
      p_module NOT IN ('ap','ar','transactions')
      OR (p_module='ap' AND
          CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END >0)
      OR (p_module='ar' AND
          CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END >0)
      OR (p_module='transactions' AND
          CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END >0)
    )
),
page_rows AS (
  SELECT u.* FROM matched u
  ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST, u.id
  LIMIT greatest(1,least(coalesce(p_page_size,10),25))
  OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
  'snapshot_id',p.snapshot_id,
  'segment',p_segment,
  'as_of',p.as_of_at,
  'source_watermark_at',p.source_watermark_at,
  'total',(SELECT count(*) FROM matched),
  'segment_total',(SELECT count(*) FROM classified WHERE included),
  'page',greatest(coalesce(p_page,1),1),
  'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
  'rows',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',u.id,
      'email',coalesce(u.email,u.id),
      'actions',CASE WHEN p_segment='wau' THEN u.actions_7 ELSE u.actions_30 END,
      'active_days',CASE WHEN p_segment='wau' THEN u.days_7 ELSE u.days_30 END,
      'last_active_at',CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END,
      'modules',jsonb_build_object(
        'ap',CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END,
        'ar',CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END,
        'transactions',CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END
      ),
      'companies',coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id',a.company_id, 'name',a.company_name,'is_test',a.is_test,
          'actions',CASE WHEN p_segment='wau' THEN a.actions_7 ELSE a.actions_30 END,
          'active_days',CASE WHEN p_segment='wau' THEN a.active_days_7 ELSE a.active_days_30 END,
          'last_active_at',CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END,
          'modules',jsonb_build_object(
            'ap',CASE WHEN p_segment='wau' THEN a.ap_7 ELSE a.ap_30 END,
            'ar',CASE WHEN p_segment='wau' THEN a.ar_7 ELSE a.ar_30 END,
            'transactions',CASE WHEN p_segment='wau' THEN a.transactions_7 ELSE a.transactions_30 END
          )
        ) ORDER BY
          (CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END) DESC NULLS LAST,a.company_id)
        FROM named_pairs a
        WHERE a.distinct_id=u.id AND (p_segment<>'wau' OR a.actions_7>0)
      ),'[]'::jsonb)
    ) ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST,u.id)
    FROM page_rows u
  ),'[]'::jsonb)
)
FROM published p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_drill_header(p_snapshot_id bigint, p_kind text, p_drill_key text, p_tab text)
 RETURNS TABLE(header jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.header
  FROM public.product_overview_drill AS d
  WHERE d.snapshot_id = p_snapshot_id
    AND d.kind = p_kind
    AND d.drill_key = p_drill_key
    AND d.tab = p_tab;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v1(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 AND c.snapshot_id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_v1(s.id) f
 WHERE f.issue_key=p_issue_key AND f.period=p_period
),
population AS MATERIALIZED(
 SELECT f.* FROM facts f WHERE
 p_segment='eligible'
 OR (p_segment='affected' AND f.failed_events>0)
 OR (p_segment='later_success' AND f.failed_events>0 AND f.followup_at IS NOT NULL)
 OR (p_segment='needs_review' AND f.failed_events>0 AND f.followup_at IS NULL)
),
named AS MATERIALIZED(
 SELECT f.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),f.company_id) AS company_name,
 coalesce(d.is_test,false) AS is_test
 FROM population f
 LEFT JOIN public.company_directory d ON d.company_uuid::text=f.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=f.company_id
),
matched AS MATERIALIZED(
 SELECT * FROM named n WHERE btrim(coalesce(p_query,''))=''
 OR n.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS MATERIALIZED(
 SELECT * FROM matched n
 ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
),
ev AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_events_v1(s.id) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period
),
users AS MATERIALIZED(
 SELECT e.company_id,e.distinct_id AS id,
 coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
 count(*)::integer AS attempts,
 count(*) FILTER(WHERE e.is_failure)::integer AS failures,
 count(*) FILTER(WHERE e.is_success)::integer AS successes,
 max(e.event_time) AS last_at
 FROM ev e JOIN paged n ON n.company_id=e.company_id
 GROUP BY e.company_id,e.distinct_id
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_list_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'issue_key',p_issue_key,'period',p_period,'segment',p_segment,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',n.company_id,'name',n.company_name,'is_test',n.is_test,
   'eligible_events',n.eligible_events,'failed_events',n.failed_events,
   'success_events',n.success_events,
   'first_failure_at',n.first_failure_at,'last_failure_at',n.last_failure_at,
   'followup_at',n.followup_at,'last_event_at',n.last_event_at,
   'observed_users',n.observed_users,
   'users',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'attempts',u.attempts,'failures',u.failures,
     'successes',u.successes,'last_at',u.last_at
    ) ORDER BY u.failures DESC,u.attempts DESC,u.id)
    FROM users u WHERE u.company_id=n.company_id
   ),'[]'::jsonb)
  ) ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id)
  FROM paged n
 ),'[]'::jsonb)
)
FROM scope s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v2(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 AND c.snapshot_id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_v2(s.id) f
 WHERE f.issue_key=p_issue_key AND f.period=p_period
),
population AS MATERIALIZED(
 SELECT f.* FROM facts f WHERE
 p_segment='eligible'
 OR (p_segment='affected' AND f.failed_events>0)
 OR (p_segment='later_success' AND f.failed_events>0 AND f.followup_at IS NOT NULL)
 OR (p_segment='needs_review' AND f.failed_events>0 AND f.followup_at IS NULL)
),
named AS MATERIALIZED(
 SELECT f.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),f.company_id) AS company_name,
 coalesce(d.is_test,false) AS is_test
 FROM population f
 LEFT JOIN public.company_directory d ON d.company_uuid::text=f.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=f.company_id
),
matched AS MATERIALIZED(
 SELECT * FROM named n WHERE btrim(coalesce(p_query,''))=''
 OR n.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS MATERIALIZED(
 SELECT * FROM matched n
 ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
),
ev AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_events_v2(s.id) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period
),
users AS MATERIALIZED(
 SELECT e.company_id,e.distinct_id AS id,
 coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
 count(*)::integer AS attempts,
 count(*) FILTER(WHERE e.is_failure)::integer AS failures,
 count(*) FILTER(WHERE e.is_success)::integer AS successes,
 max(e.event_time) AS last_at
 FROM ev e JOIN paged n ON n.company_id=e.company_id
 GROUP BY e.company_id,e.distinct_id
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_list_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'issue_key',p_issue_key,'period',p_period,'segment',p_segment,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',n.company_id,'name',n.company_name,'is_test',n.is_test,
   'eligible_events',n.eligible_events,'failed_events',n.failed_events,
   'success_events',n.success_events,
   'first_failure_at',n.first_failure_at,'last_failure_at',n.last_failure_at,
   'followup_at',n.followup_at,'last_event_at',n.last_event_at,
   'observed_users',n.observed_users,
   'users',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'attempts',u.attempts,'failures',u.failures,
     'successes',u.successes,'last_at',u.last_at
    ) ORDER BY u.failures DESC,u.attempts DESC,u.id)
    FROM users u WHERE u.company_id=n.company_id
   ),'[]'::jsonb)
  ) ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id)
  FROM paged n
 ),'[]'::jsonb)
)
FROM scope s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v3(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
 AND s.id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_v3(s.id) f
 WHERE f.issue_key=p_issue_key AND f.period=p_period
),
population AS MATERIALIZED(
 SELECT f.* FROM facts f WHERE
 p_segment='eligible'
 OR (p_segment='affected' AND f.failed_events>0)
 OR (p_segment='later_success' AND f.failed_events>0 AND f.followup_at IS NOT NULL)
 OR (p_segment='needs_review' AND f.failed_events>0 AND f.followup_at IS NULL)
),
named AS MATERIALIZED(
 SELECT f.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),f.company_id) AS company_name,
 coalesce(d.is_test,false) AS is_test
 FROM population f
 LEFT JOIN public.company_directory d ON d.company_uuid::text=f.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=f.company_id
),
matched AS MATERIALIZED(
 SELECT * FROM named n WHERE btrim(coalesce(p_query,''))=''
 OR n.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS MATERIALIZED(
 SELECT * FROM matched n
 ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
),
ev AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_events_v3(s.id) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period
),
users AS MATERIALIZED(
 SELECT e.company_id,e.distinct_id AS id,
 coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
 count(*)::integer AS attempts,
 count(*) FILTER(WHERE e.is_failure)::integer AS failures,
 count(*) FILTER(WHERE e.is_success)::integer AS successes,
 max(e.event_time) AS last_at
 FROM ev e JOIN paged n ON n.company_id=e.company_id
 GROUP BY e.company_id,e.distinct_id
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_list_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'issue_key',p_issue_key,'period',p_period,'segment',p_segment,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',n.company_id,'name',n.company_name,'is_test',n.is_test,
   'eligible_events',n.eligible_events,'failed_events',n.failed_events,
   'success_events',n.success_events,
   'first_failure_at',n.first_failure_at,'last_failure_at',n.last_failure_at,
   'followup_at',n.followup_at,'last_event_at',n.last_event_at,
   'observed_users',n.observed_users,
   'users',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'attempts',u.attempts,'failures',u.failures,
     'successes',u.successes,'last_at',u.last_at
    ) ORDER BY u.failures DESC,u.attempts DESC,u.id)
    FROM users u WHERE u.company_id=n.company_id
   ),'[]'::jsonb)
  ) ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id)
  FROM paged n
 ),'[]'::jsonb)
)
FROM scope s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v4(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
 AND s.id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_scoped_v4(s.id,p_issue_key,p_period) f
 WHERE f.issue_key=p_issue_key AND f.period=p_period
),
population AS MATERIALIZED(
 SELECT f.* FROM facts f WHERE
 p_segment='eligible'
 OR (p_segment='affected' AND f.failed_events>0)
 OR (p_segment='later_success' AND f.failed_events>0 AND f.followup_at IS NOT NULL)
 OR (p_segment='needs_review' AND f.failed_events>0 AND f.followup_at IS NULL)
),
named AS MATERIALIZED(
 SELECT f.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),f.company_id) AS company_name,
 coalesce(d.is_test,false) AS is_test
 FROM population f
 LEFT JOIN public.company_directory d ON d.company_uuid::text=f.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=f.company_id
),
matched AS MATERIALIZED(
 SELECT * FROM named n WHERE btrim(coalesce(p_query,''))=''
 OR n.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS MATERIALIZED(
 SELECT * FROM matched n
 ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
),
ev AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_events_scoped_v4(s.id,p_issue_key,p_period) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period
),
users AS MATERIALIZED(
 SELECT e.company_id,e.distinct_id AS id,
 coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
 count(*)::integer AS attempts,
 count(*) FILTER(WHERE e.is_failure)::integer AS failures,
 count(*) FILTER(WHERE e.is_success)::integer AS successes,
 max(e.event_time) AS last_at
 FROM ev e JOIN paged n ON n.company_id=e.company_id
 GROUP BY e.company_id,e.distinct_id
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_list_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'issue_key',p_issue_key,'period',p_period,'segment',p_segment,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',n.company_id,'name',n.company_name,'is_test',n.is_test,
   'eligible_events',n.eligible_events,'failed_events',n.failed_events,
   'success_events',n.success_events,
   'first_failure_at',n.first_failure_at,'last_failure_at',n.last_failure_at,
   'followup_at',n.followup_at,'last_event_at',n.last_event_at,
   'observed_users',n.observed_users,
   'users',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'attempts',u.attempts,'failures',u.failures,
     'successes',u.successes,'last_at',u.last_at
    ) ORDER BY u.failures DESC,u.attempts DESC,u.id)
    FROM users u WHERE u.company_id=n.company_id
   ),'[]'::jsonb)
  ) ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id)
  FROM paged n
 ),'[]'::jsonb)
)
FROM scope s;
$function$
;
