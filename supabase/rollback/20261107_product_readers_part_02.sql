-- Exact original public Product read RPCs, part 2/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_companies_monthly_insights_v1(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_month date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '12s'
AS $function$
WITH identity AS MATERIALIZED (
  SELECT i.company_id,i.company_name,i.integration_at,i.integration_month
  FROM metrics_private.company_monthly_identity i
  WHERE i.company_id=p_company_id AND NOT i.is_test
),
selected_month AS (
  SELECT date_trunc('month',coalesce(p_usage_month,current_date)::timestamp)::date AS month_start
),
anchor AS MATERIALIZED (
  SELECT i.company_id,i.company_name, m.month_start,
    greatest(m.month_start::timestamp AT TIME ZONE 'Asia/Kolkata',i.integration_at) AS start_at,
    (m.month_start+interval '1 month')::timestamp AT TIME ZONE 'Asia/Kolkata' AS end_at,
    wm.source_watermark_at
  FROM identity i CROSS JOIN selected_month m
  JOIN metrics_private.company_monthly_meta_v2 wm ON wm.singleton
  WHERE m.month_start>=i.integration_month
    AND p_module IN ('ap','ar','transactions','gst')
),
qualified AS MATERIALIZED (
  SELECT
    e.event_name,
    CASE
      WHEN e.event_name='Transaction Status' THEN 'status'
      WHEN e.event_name='Transaction Ledger Updated' THEN 'ledger'
      WHEN e.event_name='Transaction Type Updated' THEN 'type_change'
      WHEN e.event_name='Upload' THEN 'upload'
      WHEN e.event_name='Entity Created' THEN 'entity'
      WHEN e.event_name='Vendor Mismatch Resolved' THEN 'vendor_mismatch'
      WHEN e.event_name='Recon Processed' THEN 'reconciliation'
      WHEN e.event_name='Transaction Configuration Edited' THEN 'configuration'
      WHEN e.event_name='Invoice Bulk Edited' THEN 'invoice_edit'
      ELSE 'other'
    END AS category,
    e.event_time,
    (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') AS user_key,
    nullif(btrim(e.email),'') AS email,
    nullif(left(btrim(e.properties->>'type'),80),'') AS event_type,
    nullif(left(btrim(e.properties->>'subType'),80),'') AS sub_type,
    nullif(left(btrim(e.properties->>'entityType'),80),'') AS entity_type,
    CASE
      WHEN (e.properties->>'transactionType') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN 'Other / custom transaction type'
      ELSE nullif(left(btrim(e.properties->>'transactionType'),80),'')
    END AS transaction_type,
    nullif(left(btrim(e.properties->>'action'),80),'') AS action,
    nullif(left(btrim(e.properties->>'status'),80),'') AS status,
    nullif(left(btrim(e.properties->>'source'),80),'') AS source,
    nullif(left(btrim(e.properties->>'fileType'),120),'') AS file_type,
    nullif(left(btrim(e.properties->>'resolutionType'),80),'') AS resolution_type,
    public.company_items_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) AS items
  FROM public.events e CROSS JOIN anchor a
  WHERE e.company_id=a.company_id
    AND e.event_time>=a.start_at AND e.event_time<a.end_at
    AND e.ingested_at<=a.source_watermark_at
    AND NOT public.is_internal_email(e.email)
    AND metrics_private.company_work_module_v2(
      e.event_name,coalesce(e.properties,'{}'::jsonb)
    )=p_module
    AND (
      p_user_key IS NULL
      OR (p_user_key='' AND nullif(btrim(e.distinct_id),'') IS NULL)
      OR (p_user_key<>'' AND e.distinct_id=p_user_key)
    )
),
summary AS MATERIALIZED (
 SELECT count(*)::bigint total,
   count(DISTINCT user_key) FILTER(WHERE user_key<>'__unattributed__')::integer active_users,
   count(DISTINCT activity_day)::integer active_days,
   count(*) FILTER(WHERE user_key='__unattributed__')::integer unattributed_events,
   sum(items)::bigint item_total,
   count(items)::integer instrumented_events,
   min(event_time) first_at, max(event_time) last_at
 FROM qualified
),
slices AS MATERIALIZED (
 SELECT category,event_name,event_type,sub_type,entity_type,transaction_type,
   action,status,source,file_type,resolution_type,
   count(*)::bigint events,
   sum(items)::bigint items,
   count(items)::integer instrumented,
   max(event_time) latest_at
 FROM qualified
 GROUP BY category,event_name,event_type,sub_type,entity_type,transaction_type,
    action,status,source,file_type,resolution_type
),
categories AS MATERIALIZED (
 SELECT category,count(*)::bigint events,
   sum(items)::bigint items,count(items)::integer instrumented
 FROM qualified GROUP BY category
),
daily AS MATERIALIZED (
 SELECT activity_day,count(*)::bigint events,
    count(DISTINCT user_key) FILTER(WHERE user_key<>'__unattributed__')::integer users
 FROM qualified GROUP BY activity_day
),
sources AS MATERIALIZED (
 SELECT coalesce(source,'Not captured') AS source,count(*)::bigint events
 FROM qualified GROUP BY coalesce(source,'Not captured')
),
user_groups AS MATERIALIZED (
 SELECT user_key,
  coalesce(max(email) FILTER(WHERE email IS NOT NULL), user_key) AS label,
  count(*)::bigint events,
  count(DISTINCT activity_day)::integer active_days,
  min(event_time) first_at,max(event_time) last_at,
  count(*) FILTER(WHERE category='status')::integer status_events,
  count(*) FILTER(WHERE category='ledger')::integer ledger_events,
  count(*) FILTER(WHERE category='type_change')::integer type_events,
  count(*) FILTER(WHERE category='upload')::integer upload_events,
  count(*) FILTER(WHERE category='entity')::integer entity_events,
  count(*) FILTER(WHERE category='vendor_mismatch')::integer vendor_events,
  count(*) FILTER(WHERE category='reconciliation')::integer reconciliation_events,
  count(*) FILTER(WHERE category='configuration')::integer configuration_events,
  count(*) FILTER(WHERE category='invoice_edit')::integer invoice_edit_events,
  count(*) FILTER(WHERE category='other')::integer other_events
 FROM qualified GROUP BY user_key
),
top_users AS MATERIALIZED (
 SELECT * FROM user_groups ORDER BY events DESC,user_key LIMIT 50
)
SELECT jsonb_build_object(
 'contract','companies_monthly_drill_insights_v1',
 'company_id',a.company_id,
 'company_name',a.company_name,
 'module',p_module,
 'month',a.month_start,
 'user_key',p_user_key,
 'window_start',a.start_at,
 'window_end',a.end_at,
 'source_watermark_at',a.source_watermark_at,
 'total',s.total,
 'item_total',s.item_total,
 'instrumented_events',s.instrumented_events,
 'active_users',s.active_users,
 'active_days',s.active_days,
 'unattributed_events',s.unattributed_events,
 'first_at',s.first_at,
 'last_at',s.last_at,
 'user_groups_total',(SELECT count(*) FROM user_groups),
 'categories',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'key',c.category,'events',c.events,'items',c.items,
     'instrumented',c.instrumented
   ) ORDER BY c.events DESC,c.category) FROM categories c
 ),'[]'::jsonb),
 'slices',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'category',sl.category,'event',sl.event_name,'type',sl.event_type,
     'subtype',sl.sub_type,'entity_type',sl.entity_type,
     'transaction_type',sl.transaction_type,'action',sl.action,
     'status',sl.status,'source',sl.source,'file_type',sl.file_type,
     'resolution_type',sl.resolution_type,
     'events',sl.events,'items',sl.items,'instrumented',sl.instrumented,
     'latest_at',sl.latest_at
   ) ORDER BY sl.events DESC,sl.event_name,sl.status NULLS LAST)
   FROM slices sl
 ),'[]'::jsonb),
 'days',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'date',d.activity_day,'events',d.events,'users',d.users
   ) ORDER BY d.activity_day) FROM daily d
 ),'[]'::jsonb),
 'sources',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'source',src.source,'events',src.events
   ) ORDER BY src.events DESC,src.source) FROM sources src
 ),'[]'::jsonb),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.user_key,'label',u.label,'events',u.events,
     'active_days',u.active_days,'first_at',u.first_at,'last_at',u.last_at,
     'counts',jsonb_build_object(
       'status',u.status_events,'ledger',u.ledger_events,
       'type_change',u.type_events,'upload',u.upload_events,
       'entity',u.entity_events,'vendor_mismatch',u.vendor_events,
       'reconciliation',u.reconciliation_events,
       'configuration',u.configuration_events,'invoice_edit',u.invoice_edit_events,
       'other',u.other_events
     )
   ) ORDER BY u.events DESC,u.user_key) FROM top_users u
 ),'[]'::jsonb)
)
FROM anchor a CROSS JOIN summary s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_page_fast(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'name'::text, p_direction text DEFAULT 'asc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with args as (
  select
    greatest(coalesce(p_page, 1), 1) as page_no,
    least(greatest(coalesce(p_page_size, 10), 1), 50) as page_size,
    lower(btrim(coalesce(p_query, ''))) as q,
    case when p_usage in ('active','inactive') then p_usage else 'all' end as usage_filter,
    case when p_integration in ('Tally','Zoho Books','Unknown') then p_integration else 'all' end as integration_filter,
    case when p_sort in ('integration_date','name','ap','ar','transactions','gst','sync') then p_sort else 'integration_date' end as sort_key,
    case when lower(coalesce(p_direction, '')) = 'desc' then 'desc' else 'asc' end as sort_direction,
    case when p_from is null then null else date_trunc('month', p_from)::date end as from_month,
    case when p_to is null then null else date_trunc('month', p_to)::date end as to_month
),
company_usage as (
  select
    u.company_id,
    coalesce(sum(u.events) filter (where u.module='ap'),0)::bigint as ap,
    coalesce(sum(u.events) filter (where u.module='ar'),0)::bigint as ar,
    coalesce(sum(u.events) filter (where u.module='transactions'),0)::bigint as transactions,
    coalesce(sum(u.events) filter (where u.module='gst'),0)::bigint as gst,
    coalesce(sum(u.events) filter (where u.module='sync'),0)::bigint as sync
  from metrics_private.company_month_module_usage u
  cross join args a
  where (a.from_month is null or u.month_start >= a.from_month)
    and (a.to_month is null or u.month_start <= a.to_month)
  group by u.company_id
),
base as (
  select
    i.company_id,
    i.company_name,
    i.is_test,
    i.integration,
    i.integration_at,
    coalesce(u.ap,0)::bigint as ap,
    coalesce(u.ar,0)::bigint as ar,
    coalesce(u.transactions,0)::bigint as transactions,
    coalesce(u.gst,0)::bigint as gst,
    coalesce(u.sync,0)::bigint as sync
  from metrics_private.company_reporting_identity i
  left join company_usage u using (company_id)
),
filtered as (
  select b.*
  from base b
  cross join args a
  where (
    a.q = ''
    or lower(b.company_name) like '%' || a.q || '%'
    or exists (
      select 1
      from metrics_private.company_observed_user ou
      where ou.company_id=b.company_id
        and lower(coalesce(ou.user_email, ou.user_key)) like '%' || a.q || '%'
    )
  )
  and (a.integration_filter='all' or b.integration=a.integration_filter)
  and (
    a.usage_filter='all'
    or (a.usage_filter='active' and b.ap+b.ar+b.transactions+b.gst+b.sync > 0)
    or (a.usage_filter='inactive' and b.ap+b.ar+b.transactions+b.gst+b.sync = 0)
  )
),
ranked as (
  select
    f.*,
    row_number() over (
      order by
        case when a.sort_key='integration_date' and a.sort_direction='asc' then f.integration_at end asc nulls last,
        case when a.sort_key='integration_date' and a.sort_direction='desc' then f.integration_at end desc nulls last,
        case when a.sort_key='name' and a.sort_direction='asc' then lower(f.company_name) end asc,
        case when a.sort_key='name' and a.sort_direction='desc' then lower(f.company_name) end desc,
        case when a.sort_key='ap' and a.sort_direction='asc' then f.ap end asc,
        case when a.sort_key='ap' and a.sort_direction='desc' then f.ap end desc,
        case when a.sort_key='ar' and a.sort_direction='asc' then f.ar end asc,
        case when a.sort_key='ar' and a.sort_direction='desc' then f.ar end desc,
        case when a.sort_key='transactions' and a.sort_direction='asc' then f.transactions end asc,
        case when a.sort_key='transactions' and a.sort_direction='desc' then f.transactions end desc,
        case when a.sort_key='gst' and a.sort_direction='asc' then f.gst end asc,
        case when a.sort_key='gst' and a.sort_direction='desc' then f.gst end desc,
        case when a.sort_key='sync' and a.sort_direction='asc' then f.sync end asc,
        case when a.sort_key='sync' and a.sort_direction='desc' then f.sync end desc,
        case when a.sort_direction='asc' then f.company_id end asc,
        case when a.sort_direction='desc' then f.company_id end desc
    ) as rn
  from filtered f
  cross join args a
),
paged as (
  select r.*
  from ranked r
  cross join args a
  where r.rn > (a.page_no - 1) * a.page_size
    and r.rn <= a.page_no * a.page_size
),
user_usage as (
  select
    u.company_id,
    u.user_key,
    coalesce(sum(u.events) filter (where u.module='ap'),0)::bigint as ap,
    coalesce(sum(u.events) filter (where u.module='ar'),0)::bigint as ar,
    coalesce(sum(u.events) filter (where u.module='transactions'),0)::bigint as transactions,
    coalesce(sum(u.events) filter (where u.module='gst'),0)::bigint as gst,
    coalesce(sum(u.events) filter (where u.module='sync'),0)::bigint as sync
  from metrics_private.company_month_module_usage u
  join paged p using (company_id)
  cross join args a
  where (a.from_month is null or u.month_start >= a.from_month)
    and (a.to_month is null or u.month_start <= a.to_month)
  group by u.company_id, u.user_key
),
user_population as (
  select ou.company_id, ou.user_key, coalesce(ou.user_email, ou.user_key) as user_email
  from metrics_private.company_observed_user ou
  join paged p using (company_id)
  union
  select uu.company_id, uu.user_key, 'Unattributed activity'
  from user_usage uu
  where uu.user_key='__unattributed__'
),
rows_with_users as (
  select
    p.*,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', up.user_key,
          'email', up.user_email,
          'totals', jsonb_build_object(
            'ap', coalesce(uu.ap,0),
            'ar', coalesce(uu.ar,0),
            'transactions', coalesce(uu.transactions,0),
            'gst', coalesce(uu.gst,0),
            'sync', coalesce(uu.sync,0)
          )
        )
        order by (up.user_key='__unattributed__'), lower(up.user_email), up.user_key
      )
      from user_population up
      left join user_usage uu
        on uu.company_id=up.company_id and uu.user_key=up.user_key
      where up.company_id=p.company_id
    ), '[]'::jsonb) as users
  from paged p
),
meta as (
  select * from metrics_private.company_reporting_meta where singleton=true limit 1
)
select jsonb_build_object(
  'rows', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', r.company_id,
        'name', r.company_name,
        'integration', r.integration,
        'integration_at', r.integration_at,
        'is_test', r.is_test,
        'totals', jsonb_build_object(
          'ap', r.ap,
          'ar', r.ar,
          'transactions', r.transactions,
          'gst', r.gst,
          'sync', r.sync
        ),
        'users', r.users
      )
      order by r.rn
    )
    from rows_with_users r
  ), '[]'::jsonb),
  'total', (select count(*) from filtered),
  'page', (select page_no from args),
  'page_size', (select page_size from args),
  'available', coalesce((
    select
      case
        when p_from is null and p_to is null then true
        else m.data_start is not null and m.data_end is not null
          and (p_to is null or p_to >= m.data_start)
          and (p_from is null or p_from <= m.data_end)
      end
    from meta m
  ), false),
  'data_start', (select data_start from meta),
  'data_end', (select data_end from meta),
  'source_watermark_at', (select source_watermark_at from meta),
  'cache_refreshed_at', (select refreshed_at from meta)
);
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_snapshot(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '20s'
AS $function$
  WITH bounds AS (
    SELECT (p_from::text || 'T00:00:00+05:30')::timestamptz AS start_at,
           ((p_to + 1)::text || 'T00:00:00+05:30')::timestamptz AS end_at
  ),
  scanned AS (
    SELECT e.company_id,
           NULLIF(btrim(e.distinct_id), '') AS user_key,
           NULLIF(btrim(e.email), '') AS email,
           e.event_time,
           e.event_name,
           COALESCE(e.properties, '{}'::jsonb) AS properties,
           reverse(split_part(reverse(lower(
             CASE WHEN e.email LIKE '%<%>%'
                  THEN COALESCE(substring(e.email FROM '<([^<>]*)>[^<>]*$'), e.email)
                  ELSE e.email END
           )), '@', 1)) AS email_domain
    FROM public.events e
    JOIN public.client_company c ON c.company_id = e.company_id
    CROSS JOIN bounds
    WHERE (p_from IS NULL OR e.event_time >= bounds.start_at)
      AND (p_to IS NULL OR e.event_time < bounds.end_at)
  ),
  live AS (
    SELECT * FROM scanned
    WHERE NOT (
      scanned.email IS NOT NULL AND (
        scanned.email_domain IN ('karboncard.com', 'korefi.ai', 'aiaccountant.com', 'korefi.com')
        OR scanned.email_domain LIKE '%.karboncard.com'
        OR scanned.email_domain LIKE '%.korefi.ai'
        OR scanned.email_domain LIKE '%.aiaccountant.com'
        OR scanned.email_domain LIKE '%.korefi.com'
      )
    )
  ),
  usage AS (
    SELECT live.company_id, live.user_key,
           public.company_module_for(live.event_name, live.properties) AS module,
           COUNT(*) AS events,
           SUM(public.company_items_for(live.event_name, live.properties)) AS items
    FROM live
    GROUP BY live.company_id, live.user_key, 3
  ),
  members AS (
    SELECT DISTINCT live.company_id, live.user_key FROM live WHERE live.user_key IS NOT NULL
  ),
  emails AS (
    SELECT DISTINCT ON (live.company_id, live.user_key)
           live.company_id, live.user_key, live.email AS user_email
    FROM live
    WHERE live.user_key IS NOT NULL AND live.email IS NOT NULL
    ORDER BY live.company_id, live.user_key, live.event_time DESC
  )
  SELECT jsonb_build_object(
    'usage', (SELECT COALESCE(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
              FROM (SELECT company_id, user_key, module, events, items FROM usage WHERE module IS NOT NULL) u),
    'members', (SELECT COALESCE(jsonb_agg(to_jsonb(m)), '[]'::jsonb)
                FROM (SELECT members.company_id, members.user_key, emails.user_email
                      FROM members LEFT JOIN emails USING (company_id, user_key)) m)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_usage(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(company_id text, user_key text, module text, events bigint, items bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '20s'
AS $function$
  WITH bounds AS (
    SELECT (p_from::text || 'T00:00:00+05:30')::timestamptz AS start_at,
           ((p_to + 1)::text || 'T00:00:00+05:30')::timestamptz AS end_at
  ),
  scanned AS (
    SELECT e.company_id,
           NULLIF(btrim(e.distinct_id), '') AS user_key,
           e.event_name,
           COALESCE(e.properties, '{}'::jsonb) AS properties,
           NULLIF(btrim(e.email), '') IS NOT NULL AS has_email,
           reverse(split_part(reverse(lower(
             CASE WHEN e.email LIKE '%<%>%'
                  THEN COALESCE(substring(e.email FROM '<([^<>]*)>[^<>]*$'), e.email)
                  ELSE e.email END
           )), '@', 1)) AS email_domain
    FROM public.events e
    JOIN public.client_company c ON c.company_id = e.company_id
    CROSS JOIN bounds
    WHERE (p_from IS NULL OR e.event_time >= bounds.start_at)
      AND (p_to IS NULL OR e.event_time < bounds.end_at)
  ),
  classified AS (
    SELECT scanned.company_id,
           scanned.user_key,
           public.company_module_for(scanned.event_name, scanned.properties) AS module,
           public.company_items_for(scanned.event_name, scanned.properties) AS items
    FROM scanned
    WHERE NOT (
      scanned.has_email AND (
        scanned.email_domain IN ('karboncard.com', 'korefi.ai', 'aiaccountant.com', 'korefi.com')
        OR scanned.email_domain LIKE '%.karboncard.com'
        OR scanned.email_domain LIKE '%.korefi.ai'
        OR scanned.email_domain LIKE '%.aiaccountant.com'
        OR scanned.email_domain LIKE '%.korefi.com'
      )
    )
  )
  SELECT classified.company_id,
         classified.user_key,
         classified.module,
         COUNT(*) AS events,
         SUM(classified.items) AS items
  FROM classified
  WHERE classified.module IS NOT NULL
  GROUP BY classified.company_id, classified.user_key, classified.module
$function$
;

CREATE OR REPLACE FUNCTION public.read_company_names(p_company_id text DEFAULT NULL::text)
 RETURNS TABLE(company_id text, event_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (p.company_id)
         p.company_id AS company_id,
         public.company_usable_name(p.properties ->> 'companyName') AS event_name
  FROM public.events p
  JOIN public.client_company c ON c.company_id = p.company_id
  WHERE (p_company_id IS NULL OR p.company_id = p_company_id)
    AND p.properties ? 'companyName'
    AND public.company_usable_name(p.properties ->> 'companyName') IS NOT NULL
  ORDER BY p.company_id, p.event_time DESC
$function$
;

CREATE OR REPLACE FUNCTION public.read_company_users()
 RETURNS TABLE(company_id text, user_key text, user_email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH scanned AS (
    SELECT e.company_id,
           NULLIF(btrim(e.distinct_id), '') AS user_key,
           NULLIF(btrim(e.email), '') AS email,
           e.event_time,
           reverse(split_part(reverse(lower(
             CASE WHEN e.email LIKE '%<%>%'
                  THEN COALESCE(substring(e.email FROM '<([^<>]*)>[^<>]*$'), e.email)
                  ELSE e.email END
           )), '@', 1)) AS email_domain
    FROM public.events e
    JOIN public.client_company c ON c.company_id = e.company_id
    WHERE NULLIF(btrim(e.distinct_id), '') IS NOT NULL
  ),
  members AS (
    SELECT DISTINCT scanned.company_id, scanned.user_key
    FROM scanned
    WHERE NOT (
      scanned.email IS NOT NULL AND (
        scanned.email_domain IN ('karboncard.com', 'korefi.ai', 'aiaccountant.com', 'korefi.com')
        OR scanned.email_domain LIKE '%.karboncard.com'
        OR scanned.email_domain LIKE '%.korefi.ai'
        OR scanned.email_domain LIKE '%.aiaccountant.com'
        OR scanned.email_domain LIKE '%.korefi.com'
      )
    )
  ),
  emails AS (
    SELECT DISTINCT ON (scanned.company_id, scanned.user_key)
           scanned.company_id,
           scanned.user_key,
           scanned.email AS user_email
    FROM scanned
    WHERE scanned.email IS NOT NULL
      AND NOT (
        scanned.email_domain IN ('karboncard.com', 'korefi.ai', 'aiaccountant.com', 'korefi.com')
        OR scanned.email_domain LIKE '%.karboncard.com'
        OR scanned.email_domain LIKE '%.korefi.ai'
        OR scanned.email_domain LIKE '%.aiaccountant.com'
        OR scanned.email_domain LIKE '%.korefi.com'
      )
    ORDER BY scanned.company_id, scanned.user_key, scanned.event_time DESC
  )
  SELECT members.company_id, members.user_key, emails.user_email
  FROM members
  LEFT JOIN emails
    ON emails.company_id = members.company_id
   AND emails.user_key = members.user_key
$function$
;

CREATE OR REPLACE FUNCTION public.read_current_funnel_snapshot()
 RETURNS TABLE(snapshot_id bigint, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.snapshot_id, c.published_at, s.source_watermark_at, s.n_events
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = 'overview-funnel'
    AND c.scope_key = '';
$function$
;

CREATE OR REPLACE FUNCTION public.read_current_overview_snapshot(p_kind text)
 RETURNS TABLE(snapshot_id bigint, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.snapshot_id, c.published_at, s.source_watermark_at, s.n_events
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = p_kind
    AND c.scope_key = '';
$function$
;

CREATE OR REPLACE FUNCTION public.read_funnel_drill_header(p_snapshot_id bigint, p_node_key text, p_tab text)
 RETURNS TABLE(header jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.header
  FROM public.product_funnel_drill AS d
  WHERE d.snapshot_id = p_snapshot_id
    AND d.node_key = p_node_key
    AND d.tab = p_tab;
$function$
;

CREATE OR REPLACE FUNCTION public.read_funnel_generation(p_snapshot_id bigint)
 RETURNS TABLE(snapshot_id bigint, kind text, scope_key text, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint, is_current boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT s.id, s.kind, s.scope_key, c.published_at,
         s.source_watermark_at, s.n_events,
         EXISTS (SELECT 1
                 FROM public.product_snapshot_current AS cc
                 WHERE cc.snapshot_id = s.id) AS is_current
  FROM public.product_snapshot AS s
  LEFT JOIN public.product_snapshot_current AS c
    ON c.kind = s.kind AND c.scope_key = s.scope_key AND c.snapshot_id = s.id
  WHERE s.id = p_snapshot_id
    AND s.kind = 'overview-funnel';
$function$
;

CREATE OR REPLACE FUNCTION public.read_funnel_members(p_snapshot_id bigint, p_node_key text, p_tab text, p_limit integer, p_offset integer)
 RETURNS TABLE(card jsonb, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT f.card, t.total_count
  FROM (
    SELECT count(*) AS total_count
    FROM public.product_funnel_member AS m
    WHERE m.snapshot_id = p_snapshot_id
      AND m.node_key = p_node_key
      AND m.tab = p_tab
  ) AS t
  LEFT JOIN LATERAL (
    SELECT m.card
    FROM public.product_funnel_member AS m
    WHERE m.snapshot_id = p_snapshot_id
      AND m.node_key = p_node_key
      AND m.tab = p_tab
    ORDER BY m.sort_position
    LIMIT p_limit
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  ) AS f ON true;
$function$
;

CREATE OR REPLACE FUNCTION public.read_funnel_tab_counts(p_snapshot_id bigint, p_node_key text)
 RETURNS TABLE(tab text, member_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.tab, count(*) AS member_count
  FROM public.product_funnel_member AS m
  WHERE m.snapshot_id = p_snapshot_id
    AND m.node_key = p_node_key
  GROUP BY m.tab;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_active_chart_company_v1(p_snapshot_id bigint, p_kind text, p_key text, p_segment text, p_user_id text, p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
   CASE WHEN p_kind='weekly' THEN p_key::date
        ELSE p.current_week-28 END AS from_date,
   CASE WHEN p_kind='weekly' THEN 7 ELSE 28 END AS window_days,
   CASE WHEN p_kind='frequency' THEN p_key::int ELSE null::int END AS frequency_weeks
 FROM published p
 WHERE (p_kind='weekly' AND p_key~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        AND (p.current_week-p_key::date) BETWEEN 7 AND 84
        AND (p.current_week-p_key::date)%7=0
        AND p_segment IN ('all','returning','first_observed'))
    OR (p_kind='frequency' AND p_key IN ('1','2','3','4') AND p_segment='all')
),
focus_history AS (
 SELECT min(date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date)
        AS first_week
 FROM public.events e CROSS JOIN scope s
 WHERE e.distinct_id=p_user_id AND e.event_time<s.as_of_at
   AND e.ingested_at<=s.watermark
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
focus_frequency AS (
 SELECT count(DISTINCT date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date)::int AS weeks
 FROM public.events e CROSS JOIN scope s
 WHERE e.distinct_id=p_user_id
   AND e.event_time >= ((s.current_week-28)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < (s.current_week::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
qualified AS MATERIALIZED (
 SELECT e.distinct_id,e.email,e.event_time,e.event_name,
   (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS day,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start,
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
 WHERE e.company_id=p_company_id
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
   AND e.event_time >= (s.from_date::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < ((s.from_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
),
authorized AS (
 SELECT 1 AS allow
 FROM qualified q CROSS JOIN scope s
 CROSS JOIN focus_history f CROSS JOIN focus_frequency fw
 WHERE q.distinct_id=p_user_id
   AND CASE WHEN p_kind='weekly' THEN
      CASE p_segment WHEN 'first_observed' THEN f.first_week=s.from_date
                     WHEN 'returning' THEN f.first_week<s.from_date
                     ELSE true END
     ELSE fw.weeks=s.frequency_weeks END
 LIMIT 1
),
company_summary AS (
 SELECT count(*)::int AS core_actions,
    count(DISTINCT distinct_id)::int AS active_users,
    count(DISTINCT day)::int AS active_days,
    min(event_time) AS first_activity_at,
    max(event_time) AS last_activity_at,
    count(*) FILTER(WHERE module='ap')::int AS ap,
    count(*) FILTER(WHERE module='ar')::int AS ar,
    count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM qualified
),
members AS MATERIALIZED (
 SELECT q.distinct_id AS id,max(nullif(q.email,'')) AS email,
   count(*)::int AS actions,
   count(DISTINCT q.day)::int AS active_days,
   max(q.event_time) AS last_active_at,
   count(*) FILTER(WHERE q.module='ap')::int AS ap,
   count(*) FILTER(WHERE q.module='ar')::int AS ar,
   count(*) FILTER(WHERE q.module='transactions')::int AS transactions
 FROM qualified q GROUP BY q.distinct_id
),
weeks AS MATERIALIZED (
 SELECT week_start,count(*)::int AS actions,
    count(DISTINCT distinct_id)::int AS active_users,
    count(*) FILTER(WHERE module='ap')::int AS ap,
    count(*) FILTER(WHERE module='ar')::int AS ar,
    count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM qualified GROUP BY week_start
),
milestones AS (
 SELECT min(e.event_time) FILTER(WHERE e.event_name='Company Created') AS created_at,
   min(e.event_time) FILTER(WHERE public.is_successful_integration(e.event_name,e.properties)) AS integration_at,
   min(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS first_sync_at,
   max(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS last_sync_at
 FROM public.events e CROSS JOIN scope s
 WHERE e.company_id=p_company_id AND e.event_time<s.as_of_at
   AND e.ingested_at<=s.watermark
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
 'snapshot_id',s.snapshot_id,
 'scope',p_kind,
 'as_of',s.as_of_at,
 'source_watermark_at',s.watermark,
 'focus_user_id',p_user_id,
 'company',jsonb_build_object(
    'id',p_company_id,
    'name',coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),p_company_id),
    'is_test',coalesce(d.is_test,false)
 ),
 'window',jsonb_build_object(
    'start',(s.from_date::timestamp AT TIME ZONE 'Asia/Kolkata'),
    'end',((s.from_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata'),
    'days',s.window_days
 ),
 'stats',jsonb_build_object(
    'core_actions',a.core_actions,
    'active_users',a.active_users,'active_days',a.active_days,
    'first_activity_at',a.first_activity_at,'last_activity_at',a.last_activity_at,
    'modules',jsonb_build_object('ap',a.ap,'ar',a.ar,'transactions',a.transactions)
 ),
 'milestones',jsonb_build_object(
    'company_created_at',coalesce(cp.signed_up_at,m.created_at),
    'integration_at',m.integration_at,
    'first_independent_activity_at',a.first_activity_at,
    'first_qualifying_sync_at',m.first_sync_at,
    'last_qualifying_sync_at',m.last_sync_at
 ),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'actions',u.actions,'active_days',u.active_days,'last_active_at',u.last_active_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.transactions)
   ) ORDER BY u.actions DESC,u.id) FROM members u
 ),'[]'::jsonb),
 'weeks',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'week_start',w.week_start,'actions',w.actions,'active_users',w.active_users,
     'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.transactions)
   ) ORDER BY w.week_start) FROM weeks w
 ),'[]'::jsonb),
 'recent_events',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'at',q.event_time,'event',q.event_name,'module',q.module,
     'user_id',q.distinct_id,
     'user_email',coalesce(nullif(q.email,''),q.distinct_id)
   ) ORDER BY q.event_time DESC)
   FROM (SELECT * FROM qualified ORDER BY event_time DESC LIMIT 30) q
 ),'[]'::jsonb)
)
FROM scope s CROSS JOIN authorized x CROSS JOIN company_summary a
LEFT JOIN public.company_directory d ON d.company_uuid::text=p_company_id
LEFT JOIN public.company_profile cp ON cp.company_id=p_company_id
CROSS JOIN milestones m;
$function$
;
