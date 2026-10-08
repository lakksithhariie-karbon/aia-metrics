-- Paginated user-first drill for the independent core-work KPI contract.
-- Pins membership to the exact Overview snapshot shown in the UI.
CREATE OR REPLACE FUNCTION public.read_overview_core_users_v1(
  p_snapshot_id bigint,
  p_segment text DEFAULT 'mau',
  p_query text DEFAULT '',
  p_module text DEFAULT 'all',
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 10
)
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
$function$;

REVOKE ALL ON FUNCTION public.read_overview_core_users_v1(bigint,text,text,text,integer,integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_core_users_v1(bigint,text,text,text,integer,integer)
 TO service_role;
