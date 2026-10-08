-- User-first chart drill: same source cutoff, filters, week boundaries and
-- first-observed population as read_overview_active_charts_v1.
CREATE OR REPLACE FUNCTION public.read_overview_active_chart_users_v1(
 p_snapshot_id bigint,
 p_kind text,
 p_key text,
 p_segment text DEFAULT 'all',
 p_query text DEFAULT '',
 p_module text DEFAULT 'all',
 p_page integer DEFAULT 1,
 p_page_size integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
   (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
   s.source_watermark_at AS watermark,
   date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
     AT TIME ZONE 'Asia/Kolkata')::date AS current_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
   AND c.snapshot_id=p_snapshot_id
 LIMIT 1
),
scope AS (
 SELECT p.*,
   CASE WHEN p_kind='weekly' AND p_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN p_key::date ELSE NULL::date END AS requested_week,
   CASE WHEN p_kind='frequency' AND p_key IN ('1','2','3','4')
        THEN p_key::int ELSE NULL::int END AS requested_frequency,
   CASE WHEN p_kind='weekly' AND p_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN p_key::date ELSE (p.current_week-28)::date END AS window_date,
   CASE WHEN p_kind='weekly' THEN 7 ELSE 28 END AS window_days
 FROM published p
 WHERE (p_kind='weekly'
        AND p_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        AND (p.current_week-p_key::date) BETWEEN 7 AND 84
        AND (p.current_week-p_key::date)%7=0
        AND p_segment IN ('all','returning','first_observed'))
    OR (p_kind='frequency'
        AND p_key IN ('1','2','3','4') AND p_segment='all')
),
valid_week_pairs AS MATERIALIZED (
 SELECT DISTINCT e.distinct_id,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start
 FROM public.events e CROSS JOIN scope s
 WHERE e.event_time < s.as_of_at
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.event_name <> 'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
),
first_week AS (
 SELECT distinct_id,min(week_start) AS first_week
 FROM valid_week_pairs GROUP BY distinct_id
),
four_week_frequency AS (
 SELECT distinct_id,count(*)::integer AS weeks
 FROM valid_week_pairs q CROSS JOIN scope s
 WHERE q.week_start >= s.current_week-28
   AND q.week_start < s.current_week
 GROUP BY distinct_id
),
qualified_window AS MATERIALIZED (
 SELECT e.distinct_id,e.company_id,
   nullif(e.email,'') AS email,nullif(e.company,'') AS event_company_name,
   e.event_time,(e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
   CASE
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
       OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
       OR e.event_name='Invoice Bulk Edited' THEN 'ar'
     ELSE 'transactions'
   END AS module
 FROM public.events e CROSS JOIN scope s
 WHERE e.event_time >= (s.window_date::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < ((s.window_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.company_id IS NOT NULL AND e.company_id <> ''
   AND e.event_name <> 'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
),
per_company AS MATERIALIZED (
 SELECT e.distinct_id,e.company_id,
   max(e.email) AS email,max(e.event_company_name) AS event_company_name,
   count(*)::int AS actions,count(DISTINCT e.activity_day)::int AS active_days,
   max(e.event_time) AS last_active_at,
   count(*) FILTER(WHERE e.module='ap')::int AS ap,
   count(*) FILTER(WHERE e.module='ar')::int AS ar,
   count(*) FILTER(WHERE e.module='transactions')::int AS transactions
 FROM qualified_window e GROUP BY e.distinct_id,e.company_id
),
named_company AS MATERIALIZED (
 SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
                        a.event_company_name,a.company_id) AS company_name,
        coalesce(d.is_test,false) AS is_test
 FROM per_company a
 LEFT JOIN public.company_directory d ON d.company_uuid::text=a.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=a.company_id
),
per_user AS MATERIALIZED (
 SELECT q.distinct_id AS id,max(q.email) AS email,
   count(*)::int AS actions,
   count(DISTINCT q.activity_day)::int AS active_days,
   max(q.event_time) AS last_active_at,
   count(*) FILTER(WHERE q.module='ap')::int AS ap,
   count(*) FILTER(WHERE q.module='ar')::int AS ar,
   count(*) FILTER(WHERE q.module='transactions')::int AS transactions
 FROM qualified_window q GROUP BY q.distinct_id
),
qualified_users AS MATERIALIZED (
 SELECT u.*
 FROM per_user u
 JOIN scope s ON true
 LEFT JOIN first_week f ON f.distinct_id=u.id
 LEFT JOIN four_week_frequency fw ON fw.distinct_id=u.id
 WHERE CASE WHEN p_kind='weekly' THEN
   CASE p_segment WHEN 'first_observed' THEN f.first_week=s.requested_week
                  WHEN 'returning' THEN f.first_week<s.requested_week
                  ELSE true END
 ELSE fw.weeks=s.requested_frequency END
),
matched AS MATERIALIZED (
 SELECT u.* FROM qualified_users u
 WHERE (coalesce(btrim(p_query),'')=''
        OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
        OR EXISTS (
          SELECT 1 FROM named_company c WHERE c.distinct_id=u.id
            AND c.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
        ))
   AND (p_module NOT IN ('ap','ar','transactions')
        OR (p_module='ap' AND u.ap>0)
        OR (p_module='ar' AND u.ar>0)
        OR (p_module='transactions' AND u.transactions>0))
),
paged AS (
 SELECT u.* FROM matched u
 ORDER BY u.last_active_at DESC NULLS LAST,u.id
 LIMIT greatest(1,least(coalesce(p_page_size,10),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)
        *greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
 'contract','independent_core_active_chart_users_v1',
 'snapshot_id',s.snapshot_id,
 'kind',p_kind,'key',p_key,'segment',p_segment,
 'as_of',s.as_of_at,'source_watermark_at',s.watermark,
 'window_start',s.window_date,
 'window_end',s.window_date+s.window_days,
 'segment_total',(SELECT count(*) FROM qualified_users),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
 'rows',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'actions',u.actions,'active_days',u.active_days,
     'last_active_at',u.last_active_at,
     'modules',jsonb_build_object(
       'ap',u.ap,'ar',u.ar,'transactions',u.transactions
     ),
     'companies',coalesce((
       SELECT jsonb_agg(jsonb_build_object(
         'id',c.company_id,'name',c.company_name,'is_test',c.is_test,
         'actions',c.actions,'active_days',c.active_days,
         'last_active_at',c.last_active_at,
         'modules',jsonb_build_object(
           'ap',c.ap,'ar',c.ar,'transactions',c.transactions
         )
       ) ORDER BY c.last_active_at DESC NULLS LAST,c.company_id)
       FROM named_company c WHERE c.distinct_id=u.id
     ),'[]'::jsonb)
   ) ORDER BY u.last_active_at DESC NULLS LAST,u.id)
   FROM paged u
 ),'[]'::jsonb)
)
FROM scope s;
$function$;

REVOKE ALL ON FUNCTION public.read_overview_active_chart_users_v1(
 bigint,text,text,text,text,text,integer,integer
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_active_chart_users_v1(
 bigint,text,text,text,text,text,integer,integer
) TO service_role;
