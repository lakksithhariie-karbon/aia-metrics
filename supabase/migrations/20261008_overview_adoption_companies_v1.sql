-- Searchable, paginated company-first drill for adoption outcomes,
-- journey stages and overlapping module activities.
-- Every segment is computed from the same 403 canonical company facts.
CREATE OR REPLACE FUNCTION public.read_overview_adoption_companies_v1(
 p_snapshot_id bigint,
 p_segment text DEFAULT 'all',
 p_query text DEFAULT '',
 p_page integer DEFAULT 1,
 p_page_size integer DEFAULT 8
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
 s.source_watermark_at
 FROM public.product_snapshot_current c JOIN public.product_snapshot s
 ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
 AND s.source_status='ok'
 LIMIT 1
),
facts AS MATERIALIZED (
 SELECT f.* FROM published p CROSS JOIN LATERAL
 public.overview_adoption_company_facts_v1(p.snapshot_id) f
),
selection AS MATERIALIZED (
 SELECT f.*
 FROM facts f
 WHERE CASE p_segment
  WHEN 'all' THEN true
  WHEN 'core_7d' THEN f.first_core_7d_at IS NOT NULL
  WHEN 'not_core_7d' THEN f.first_core_7d_at IS NULL
  WHEN 'value_28d' THEN f.value_at IS NOT NULL
  WHEN 'not_value_28d' THEN f.value_at IS NULL
  WHEN 'sustained_28d' THEN f.active_weeks>=2
  WHEN 'not_sustained_28d' THEN f.active_weeks<2
  WHEN 'qualifying_sync' THEN f.first_sync_after_core_at IS NOT NULL
  WHEN 'stalled_after_integration' THEN f.first_core_7d_at IS NULL
  WHEN 'stalled_before_sync' THEN f.first_core_7d_at IS NOT NULL AND
     f.first_sync_after_core_at IS NULL
  WHEN 'module_ap' THEN f.first_core_7d_at IS NOT NULL AND f.ap_actions>0
  WHEN 'module_ar' THEN f.first_core_7d_at IS NOT NULL AND f.ar_actions>0
  WHEN 'module_transactions' THEN f.first_core_7d_at IS NOT NULL AND f.transaction_actions>0
  ELSE f.first_core_7d_at IS NOT NULL AND
    p_segment IN (
     'bill_upload','bill_entity','vendor_mismatch',
     'invoice_upload','invoice_entity','invoice_bulk',
     'statement_upload','transaction_ledger',
     'transaction_status','transaction_type'
    ) AND f.step_flags->>p_segment='true'
 END
),
matched AS MATERIALIZED (
 SELECT f.* FROM selection f
 WHERE btrim(coalesce(p_query,''))=''
 OR f.company_name ILIKE '%'||left(btrim(p_query),70)||'%'
 OR f.integration_type ILIKE '%'||left(btrim(p_query),70)||'%'
),
paged AS (
 SELECT f.* FROM matched f
 ORDER BY f.integrated_at DESC,f.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
)
SELECT jsonb_build_object(
 'contract','mature_independent_adoption_companies_v1',
 'snapshot_id',p.snapshot_id,
 'as_of',p.as_of_at,
 'source_watermark_at',p.source_watermark_at,
 'segment',p_segment,
 'segment_total',(SELECT count(*) FROM selection),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
 SELECT jsonb_agg(jsonb_build_object(
  'id',f.company_id,
  'name',f.company_name,
  'integration_type',f.integration_type,
  'is_test',f.is_test,
  'integration_at',f.integrated_at,
  'first_core_7d_at',f.first_core_7d_at,
  'first_core_28d_at',f.first_core_28d_at,
  'sync_after_core_at',f.first_sync_after_core_at,
  'value_at',f.value_at,
  'active_weeks',f.active_weeks,
  'core_actions',f.core_actions,
  'last_core_at',f.last_core_at,
  'modules',jsonb_build_object('ap',f.ap_actions,'ar',f.ar_actions,
                                'transactions',f.transaction_actions),
  'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'core_actions',u.core_actions,
     'last_core_at',u.last_core_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.txn)
   ) ORDER BY u.core_actions DESC,u.id)
   FROM (
    SELECT e.distinct_id AS id,coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
     count(*)::integer AS core_actions,
     max(e.event_time) AS last_core_at,
     count(*) FILTER(WHERE
      (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
      OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
      OR e.event_name='Vendor Mismatch Resolved')::integer AS ap,
     count(*) FILTER(WHERE
      (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
      OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
      OR e.event_name='Invoice Bulk Edited')::integer AS ar,
     count(*) FILTER(WHERE NOT (
      (e.event_name='Upload' AND lower(btrim(e.properties->>'type')) IN ('bill','invoice'))
      OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType')) IN ('bill','invoice'))
      OR e.event_name IN ('Vendor Mismatch Resolved','Invoice Bulk Edited')
     ))::integer AS txn
    FROM public.events e
    WHERE e.company_id=f.company_id
      AND e.event_time>=f.integrated_at
      AND e.event_time<f.integrated_at+interval '28 days'
      AND e.event_time<p.as_of_at
      AND e.ingested_at<=p.source_watermark_at
      AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
      AND e.event_name<>'Accounting Sync'
      AND public.is_core_activity(e.event_name,e.properties)
      AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
      AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    GROUP BY e.distinct_id
   ) u
  ),'[]'::jsonb)
 ) ORDER BY f.integrated_at DESC,f.company_id)
 FROM paged f
 ),'[]'::jsonb)
)
FROM published p;
$function$;

REVOKE ALL ON FUNCTION public.read_overview_adoption_companies_v1(
 bigint,text,text,integer,integer
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_companies_v1(
 bigint,text,text,integer,integer
) TO service_role;
