-- Exact original Product Analytics Usage/Lifecycle functions, before any routing change.
-- Products Features/OLAP deliberately not backed up or modified, they use teammate schemas.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.product_analytics_lifecycle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
WITH 
excluded_email_events AS MATERIALIZED (SELECT user_id,distinct_id,company_id FROM public.events WHERE (lower(btrim(coalesce(email,''))) IN ('testdemo@gmail.com','jeffrey30@gmail.com','abhishekdemo@gmail.com','abhi.demo@gmail.com','harbhajanscompanydemo@gmail.com','akhila+21@g.com','abhishekzohodemo@gmail.com','abhishekaiademo@gmail.com') OR strpos(lower(btrim(coalesce(email,''))),'aiaccountant.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'karboncard.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'@g.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'@korefi.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'@korefi.ai')>0)),
excluded_actors AS MATERIALIZED (SELECT DISTINCT coalesce(nullif(user_id,''),nullif(distinct_id,'')) AS actor FROM excluded_email_events WHERE coalesce(nullif(user_id,''),nullif(distinct_id,'')) IS NOT NULL),
excluded_companies AS MATERIALIZED (
 SELECT company_id FROM excluded_email_events WHERE nullif(company_id,'') IS NOT NULL
 UNION
 SELECT e.company_id FROM public.events e JOIN excluded_actors x ON x.actor=coalesce(nullif(e.user_id,''),nullif(e.distinct_id,'')) WHERE nullif(e.company_id,'') IS NOT NULL
),
eligible_actor_events AS NOT MATERIALIZED (SELECT e.* FROM public.events e WHERE NOT (lower(btrim(coalesce(e.email,''))) IN ('testdemo@gmail.com','jeffrey30@gmail.com','abhishekdemo@gmail.com','abhi.demo@gmail.com','harbhajanscompanydemo@gmail.com','akhila+21@g.com','abhishekzohodemo@gmail.com','abhishekaiademo@gmail.com') OR strpos(lower(btrim(coalesce(e.email,''))),'aiaccountant.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'karboncard.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'@g.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'@korefi.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'@korefi.ai')>0) AND NOT EXISTS(SELECT 1 FROM excluded_actors x WHERE x.actor=coalesce(nullif(e.user_id,''),nullif(e.distinct_id,'')))),
eligible_events AS NOT MATERIALIZED (SELECT e.* FROM eligible_actor_events e WHERE NOT EXISTS(SELECT 1 FROM excluded_companies x WHERE x.company_id=e.company_id)),
actor_history AS MATERIALIZED (SELECT event_time,event_name,email,coalesce(nullif(user_id,''),nullif(distinct_id,'')) AS actor FROM eligible_actor_events WHERE event_time<=now()),
base AS MATERIALIZED (SELECT *,coalesce(nullif(user_id,''),nullif(distinct_id,'')) AS actor FROM eligible_events WHERE event_time<=now()),
subjects AS (
 SELECT 'user'::text AS kind,actor AS id,min(event_time) AS first_seen,min(event_time) FILTER(WHERE event_name='Sign Up') AS created_at FROM actor_history WHERE actor IS NOT NULL GROUP BY actor
 UNION ALL
 SELECT 'company',company_id,min(event_time),min(event_time) FILTER(WHERE event_name='Company Created') FROM base WHERE nullif(company_id,'') IS NOT NULL GROUP BY company_id
),
roster AS (SELECT * FROM subjects UNION ALL SELECT 'company',company_uuid::text,NULL::timestamptz,NULL::timestamptz FROM public.company_directory d WHERE NOT EXISTS(SELECT 1 FROM excluded_companies x WHERE x.company_id=d.company_uuid::text) AND NOT EXISTS(SELECT 1 FROM subjects s WHERE s.kind='company' AND s.id=d.company_uuid::text)),
user_labels AS (SELECT DISTINCT ON(actor) actor,email FROM actor_history WHERE actor IS NOT NULL AND nullif(email,'') IS NOT NULL ORDER BY actor,event_time DESC),
company_labels AS (SELECT DISTINCT ON(company_id) company_id,coalesce(nullif(properties->>'companyName',''),nullif(company,'')) AS name FROM base WHERE nullif(company_id,'') IS NOT NULL AND coalesce(nullif(properties->>'companyName',''),nullif(company,'')) IS NOT NULL ORDER BY company_id,event_time DESC),
dedup AS (SELECT DISTINCT ON(insert_id) * FROM base WHERE insert_id IS NOT NULL AND event_name IN ('Entity Created','Accounting Sync') ORDER BY insert_id,ingested_at DESC NULLS LAST),
classified AS (SELECT *,CASE WHEN event_name='Entity Created' AND properties->>'entityType'='bill' THEN 'AP' WHEN event_name='Entity Created' AND properties->>'entityType'='invoice' THEN 'AR' WHEN event_name='Accounting Sync' AND properties->'sync_items'='["transactions"]'::jsonb THEN 'TXN' END AS module,CASE WHEN event_name='Entity Created' THEN 1::numeric WHEN jsonb_typeof(properties->'items_count')='number' THEN (properties->>'items_count')::numeric END AS amount FROM dedup),
qualified AS MATERIALIZED (SELECT *,to_char(event_time AT TIME ZONE 'Asia/Kolkata','YYYY-MM') AS month FROM classified WHERE module IS NOT NULL AND amount>0 AND amount=trunc(amount) AND amount<=9007199254740991),
activity AS (
 SELECT 'user'::text AS kind,actor AS id,month,module,sum(amount) AS value FROM qualified WHERE actor IS NOT NULL GROUP BY actor,month,module
 UNION ALL
 SELECT 'company',company_id,month,module,sum(amount) FROM qualified WHERE nullif(company_id,'') IS NOT NULL GROUP BY company_id,month,module
),
monthly AS (SELECT kind,id,month,jsonb_object_agg(module,value) AS module_values FROM activity GROUP BY kind,id,month),
cells AS (SELECT kind,id,jsonb_object_agg(month,module_values) AS cells FROM monthly GROUP BY kind,id)
SELECT jsonb_build_object('entities',coalesce((SELECT jsonb_agg(jsonb_build_object('kind',r.kind,'id',r.id,'name',CASE WHEN r.kind='user' THEN coalesce(u.email,r.id) ELSE coalesce(nullif(d.company_name,''),l.name,r.id) END,'firstSeen',to_char(r.first_seen AT TIME ZONE 'Asia/Kolkata','YYYY-MM'),'createdMonth',to_char(r.created_at AT TIME ZONE 'Asia/Kolkata','YYYY-MM'),'cells',coalesce(c.cells,'{}'::jsonb))) FROM roster r LEFT JOIN cells c ON c.kind=r.kind AND c.id=r.id LEFT JOIN user_labels u ON r.kind='user' AND u.actor=r.id LEFT JOIN company_labels l ON r.kind='company' AND l.company_id=r.id LEFT JOIN public.company_directory d ON r.kind='company' AND d.company_uuid::text=r.id),'[]'::jsonb),'meta',jsonb_build_object('projectRef','hdgbmcerogqfocyxdnpw','fetchedAt',now(),'firstEventAt',(SELECT min(event_time) FROM base),'lastEventAt',(SELECT max(event_time) FROM base),'unattributedUserSuccessEvents',(SELECT count(*) FROM qualified WHERE actor IS NULL),'unattributedCompanySuccessEvents',(SELECT count(*) FROM qualified WHERE nullif(company_id,'') IS NULL))) AS payload
$function$
;

CREATE OR REPLACE FUNCTION public.product_analytics_usage(from_month text, to_month text, time_group text, module_filter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
BEGIN
 IF from_month IS NULL OR to_month IS NULL OR from_month !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' OR to_month !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' OR from_month>to_month THEN RAISE EXCEPTION 'Invalid month range'; END IF;
 IF (to_month||'-01')::date >= (from_month||'-01')::date + interval '24 months' THEN RAISE EXCEPTION 'Maximum range is 24 months'; END IF;
 IF time_group IS NULL OR time_group NOT IN ('month','week') OR module_filter IS NULL OR module_filter NOT IN ('all','AP','AR','TXN') THEN RAISE EXCEPTION 'Invalid analytics options'; END IF;
 RETURN (WITH 
excluded_email_events AS MATERIALIZED (SELECT user_id,distinct_id,company_id FROM public.events WHERE (lower(btrim(coalesce(email,''))) IN ('testdemo@gmail.com','jeffrey30@gmail.com','abhishekdemo@gmail.com','abhi.demo@gmail.com','harbhajanscompanydemo@gmail.com','akhila+21@g.com','abhishekzohodemo@gmail.com','abhishekaiademo@gmail.com') OR strpos(lower(btrim(coalesce(email,''))),'aiaccountant.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'karboncard.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'@g.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'@korefi.com')>0 OR strpos(lower(btrim(coalesce(email,''))),'@korefi.ai')>0)),
excluded_actors AS MATERIALIZED (SELECT DISTINCT coalesce(nullif(user_id,''),nullif(distinct_id,'')) AS actor FROM excluded_email_events WHERE coalesce(nullif(user_id,''),nullif(distinct_id,'')) IS NOT NULL),
excluded_companies AS MATERIALIZED (
 SELECT company_id FROM excluded_email_events WHERE nullif(company_id,'') IS NOT NULL
 UNION
 SELECT e.company_id FROM public.events e JOIN excluded_actors x ON x.actor=coalesce(nullif(e.user_id,''),nullif(e.distinct_id,'')) WHERE nullif(e.company_id,'') IS NOT NULL
),
eligible_actor_events AS NOT MATERIALIZED (SELECT e.* FROM public.events e WHERE NOT (lower(btrim(coalesce(e.email,''))) IN ('testdemo@gmail.com','jeffrey30@gmail.com','abhishekdemo@gmail.com','abhi.demo@gmail.com','harbhajanscompanydemo@gmail.com','akhila+21@g.com','abhishekzohodemo@gmail.com','abhishekaiademo@gmail.com') OR strpos(lower(btrim(coalesce(e.email,''))),'aiaccountant.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'karboncard.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'@g.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'@korefi.com')>0 OR strpos(lower(btrim(coalesce(e.email,''))),'@korefi.ai')>0) AND NOT EXISTS(SELECT 1 FROM excluded_actors x WHERE x.actor=coalesce(nullif(e.user_id,''),nullif(e.distinct_id,'')))),
eligible_events AS NOT MATERIALIZED (SELECT e.* FROM eligible_actor_events e WHERE NOT EXISTS(SELECT 1 FROM excluded_companies x WHERE x.company_id=e.company_id)),
bounds AS (SELECT (from_month || '-01')::timestamp AT TIME ZONE 'Asia/Kolkata' AS start_at, ((to_month || '-01')::date + interval '1 month') AT TIME ZONE 'Asia/Kolkata' AS end_at),
ranged AS MATERIALIZED (
 SELECT e.* FROM eligible_events e, bounds b WHERE e.event_time >= b.start_at AND e.event_time < b.end_at
 AND e.event_name IN ('Entity Created','Accounting Sync')
),
dedup AS (
 SELECT DISTINCT ON (insert_id) * FROM ranged WHERE insert_id IS NOT NULL ORDER BY insert_id, ingested_at DESC NULLS LAST
),
classified AS MATERIALIZED (
 SELECT *, CASE
 WHEN event_name='Entity Created' AND properties->>'entityType'='bill' THEN 'AP'
 WHEN event_name='Entity Created' AND properties->>'entityType'='invoice' THEN 'AR'
 WHEN event_name='Accounting Sync' AND properties->'sync_items'='["transactions"]'::jsonb THEN 'TXN'
 END AS module,
 CASE WHEN event_name='Entity Created' THEN 1::numeric
 WHEN jsonb_typeof(properties->'items_count')='number' THEN (properties->>'items_count')::numeric
 ELSE NULL END AS amount
 FROM dedup
),
qualified AS MATERIALIZED (
 SELECT *, coalesce(nullif(user_id,''),nullif(distinct_id,'')) AS actor,
 to_char(date_trunc(time_group,event_time AT TIME ZONE 'Asia/Kolkata'),'YYYY-MM-DD') AS period_key
 FROM classified WHERE (module_filter='all' OR module=module_filter) AND module IS NOT NULL AND nullif(company_id,'') IS NOT NULL
 AND amount > 0 AND amount=trunc(amount) AND amount<=9007199254740991
 
),
integrated AS (
 SELECT company_id, min(event_time) AS integrated_at FROM eligible_events,bounds
 WHERE event_name='Integration status' AND properties->>'status'='Success'
 AND properties->>'type' IN ('tally','zoho') AND nullif(company_id,'') IS NOT NULL AND event_time<bounds.end_at
 GROUP BY company_id
),
roster AS (SELECT company_id FROM qualified UNION SELECT company_id FROM integrated),
labels AS (
 SELECT DISTINCT ON(e.company_id) e.company_id, coalesce(nullif(e.properties->>'companyName',''),nullif(e.company,'')) AS name
 FROM eligible_events e JOIN roster r ON r.company_id=e.company_id
 WHERE coalesce(nullif(e.properties->>'companyName',''),nullif(e.company,'')) IS NOT NULL
 ORDER BY e.company_id, e.event_time DESC, e.ingested_at DESC
),
module_totals AS (SELECT company_id,period_key,module,sum(amount) AS value FROM qualified GROUP BY company_id,period_key,module),
period_totals AS (SELECT company_id,period_key,jsonb_object_agg(module,value) AS modules FROM module_totals GROUP BY company_id,period_key),
cells AS (SELECT company_id,jsonb_object_agg(period_key,modules) AS cells FROM period_totals GROUP BY company_id),
summary AS (SELECT company_id,sum(amount) AS total,count(distinct period_key) AS active,count(distinct module) AS modules,count(distinct actor) AS users FROM qualified GROUP BY company_id),
pair_modules AS (SELECT company_id,actor,period_key,module,sum(amount) AS value FROM qualified GROUP BY company_id,actor,period_key,module),
pair_periods AS (SELECT company_id,actor,period_key,jsonb_object_agg(module,value) AS modules FROM pair_modules GROUP BY company_id,actor,period_key),
pair_cells AS (SELECT company_id,actor,jsonb_object_agg(period_key,modules) AS cells FROM pair_periods GROUP BY company_id,actor),
actor_labels AS (SELECT DISTINCT ON(actor) actor,nullif(email,'') AS email FROM qualified WHERE actor IS NOT NULL AND nullif(email,'') IS NOT NULL ORDER BY actor,event_time DESC,insert_id),
pair_summary AS (SELECT company_id,actor,sum(amount) AS total,count(distinct period_key) AS active,count(distinct module) AS modules FROM qualified GROUP BY company_id,actor),
pairs AS (SELECT jsonb_build_object('companyId',s.company_id,'userId',s.actor,'userName',coalesce(l.email,s.actor,'Unattributed user'),'cells',c.cells,'total',s.total,'active',s.active,'modules',s.modules) AS value FROM pair_summary s JOIN pair_cells c ON c.company_id=s.company_id AND c.actor IS NOT DISTINCT FROM s.actor LEFT JOIN actor_labels l ON l.actor=s.actor),
rows AS (
 SELECT jsonb_build_object('company',jsonb_build_object('id',r.company_id,'name',coalesce(nullif(d.company_name,''),l.name,r.company_id),'integrated',i.company_id IS NOT NULL),
 'cells',coalesce(c.cells,'{}'::jsonb),'total',coalesce(s.total,0),'active',coalesce(s.active,0),'modules',coalesce(s.modules,0),'users',coalesce(s.users,0)) AS value
 FROM roster r LEFT JOIN labels l USING(company_id) LEFT JOIN integrated i USING(company_id)
 LEFT JOIN public.company_directory d ON d.company_uuid::text=r.company_id
 LEFT JOIN cells c USING(company_id) LEFT JOIN summary s USING(company_id)
)
SELECT jsonb_build_object(
 'rows',coalesce((SELECT jsonb_agg(value ORDER BY value->'company'->>'id') FROM rows),'[]'::jsonb),
 'pairs',coalesce((SELECT jsonb_agg(value) FROM pairs),'[]'::jsonb),
 'meta',jsonb_build_object('fetchedAt',now(),'firstEventAt',(SELECT min(event_time) FROM eligible_events),'lastEventAt',(SELECT max(event_time) FROM eligible_events),
 'missingCompanyEvents',(SELECT count(*) FROM classified WHERE module IS NOT NULL AND nullif(company_id,'') IS NULL),
 'invalidTxnCounts',(SELECT count(*) FROM classified WHERE module='TXN' AND (amount IS NULL OR amount<0 OR amount<>trunc(amount) OR amount>9007199254740991)),
 'mixedTxnSyncEvents',(SELECT count(*) FROM dedup WHERE event_name='Accounting Sync' AND properties->'sync_items' @> '["transactions"]'::jsonb AND properties->'sync_items'<>'["transactions"]'::jsonb),
 'missingInsertIds',(SELECT count(*) FROM ranged WHERE insert_id IS NULL),
 'source','public.events','projectRef','hdgbmcerogqfocyxdnpw')) AS payload);
END;
$function$
;
