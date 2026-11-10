-- Reconstructs the user-activity portion of live Overview directly from
-- frozen Product events. Does NOT publish snapshots, alter source watermarks,
-- or change any existing reader/writer path.
-- Recorded Nov 5 generation used these exact semantics:
-- - IST calendar-day DAU; rolling 7/14 and 30/60-day WAU/MAU
-- - client companies; core activity; exclude internal-user emails
-- - exclude events ingested after the provided source watermark
-- - INCLUDE Accounting Sync and directory-marked test companies for legacy
--   headline parity (independent-core dashboard has different stricter rules).
-- The full 5-kind Overview builder must be validated before publication.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_activity_source_v1(
 p_as_of_at timestamptz, p_source_watermark_at timestamptz)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '35s'
AS $body$
WITH p AS (
  SELECT p_as_of_at AS as_of_at,p_source_watermark_at AS wm
  WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
    AND p_as_of_at >= p_source_watermark_at
), qualified AS MATERIALIZED (
  SELECT e.distinct_id,e.company_id,e.event_time
  FROM "01_product_schema".events e
  JOIN "01_product_schema".client_company c ON c.company_id=e.company_id
  CROSS JOIN p
  WHERE e.event_time >= p.as_of_at-interval '60 days'
    AND e.event_time < p.as_of_at
    AND e.ingested_at <= p.wm
    AND NULLIF(e.distinct_id,'') IS NOT NULL
    AND "01_product_schema".is_core_activity(e.event_name,e.properties)
    AND NOT "01_product_schema".is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
  'contract','overview_activity_source_v1',
  'as_of',p.as_of_at,'source_watermark_at',p.wm,
  'timezone','Asia/Kolkata',
  'dau',count(DISTINCT q.distinct_id) FILTER (
    WHERE q.event_time >= (date_trunc('day',
      p.as_of_at AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')
  ),
  'wau_current',count(DISTINCT q.distinct_id) FILTER (
    WHERE q.event_time >= p.as_of_at-interval '7 days'
  ),
  'wau_previous',count(DISTINCT q.distinct_id) FILTER (
    WHERE q.event_time >= p.as_of_at-interval '14 days'
      AND q.event_time < p.as_of_at-interval '7 days'
  ),
  'mau_current',count(DISTINCT q.distinct_id) FILTER (
    WHERE q.event_time >= p.as_of_at-interval '30 days'
  ),
  'mau_previous',count(DISTINCT q.distinct_id) FILTER (
    WHERE q.event_time < p.as_of_at-interval '30 days'
  ),
  'wau_companies',count(DISTINCT q.company_id) FILTER (
    WHERE q.event_time >= p.as_of_at-interval '7 days'
  ),
  'mau_companies',count(DISTINCT q.company_id) FILTER (
    WHERE q.event_time >= p.as_of_at-interval '30 days'
  )
)
FROM p LEFT JOIN qualified q ON true
GROUP BY p.as_of_at,p.wm;
$body$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_activity_source_v1(timestamptz,timestamptz)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_activity_source_v1(timestamptz,timestamptz)
  TO service_role;
