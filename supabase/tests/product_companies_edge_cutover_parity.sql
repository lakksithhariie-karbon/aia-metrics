-- Read-only semantic compatibility check for Companies Edge v2 reader rewrite.
-- Unlike jsonb equality of whole context rows, compare unordered arrays as multisets.
-- Expected all missing/extra counts zero, dates/watermarks match.
WITH src AS (SELECT * FROM public.read_companies_context()),
dst AS (SELECT * FROM "01_product_schema".read_companies_context())
SELECT
 (SELECT data_start FROM src) IS NOT DISTINCT FROM (SELECT data_start FROM dst) start_date_ok,
 (SELECT data_end FROM src) IS NOT DISTINCT FROM (SELECT data_end FROM dst) end_date_ok,
 (SELECT watermark FROM src) IS NOT DISTINCT FROM (SELECT watermark FROM dst) watermark_ok,
 (SELECT count(*) FROM (SELECT value FROM src,LATERAL jsonb_array_elements(src.clients) value
  EXCEPT ALL SELECT value FROM dst,LATERAL jsonb_array_elements(dst.clients) value)x) missing_clients,
 (SELECT count(*) FROM (SELECT value FROM dst,LATERAL jsonb_array_elements(dst.clients) value
  EXCEPT ALL SELECT value FROM src,LATERAL jsonb_array_elements(src.clients) value)x) extra_clients,
 (SELECT count(*) FROM (SELECT value FROM src,LATERAL jsonb_array_elements(src.directory) value
  EXCEPT ALL SELECT value FROM dst,LATERAL jsonb_array_elements(dst.directory) value)x) missing_directory,
 (SELECT count(*) FROM (SELECT value FROM dst,LATERAL jsonb_array_elements(dst.directory) value
  EXCEPT ALL SELECT value FROM src,LATERAL jsonb_array_elements(src.directory) value)x) extra_directory,
 (SELECT count(*) FROM (SELECT value FROM src,LATERAL jsonb_array_elements(src.integrations) value
  EXCEPT ALL SELECT value FROM dst,LATERAL jsonb_array_elements(dst.integrations) value)x) missing_integrations,
 (SELECT count(*) FROM (SELECT value FROM dst,LATERAL jsonb_array_elements(dst.integrations) value
  EXCEPT ALL SELECT value FROM src,LATERAL jsonb_array_elements(src.integrations) value)x) extra_integrations;

-- Confirm the staff-filtered membership reader provides the same user labels
-- as the existing 5 most-recent-event fallback, sampled deterministically.
-- No personal emails are selected out of the query, only aggregate counts.
WITH sampled AS (
 SELECT company_id,user_key,user_email FROM public.read_company_users()
 WHERE user_key IS NOT NULL AND user_key<>''
 ORDER BY company_id,user_key LIMIT 150
), labels AS (
 SELECT m.user_email,
 (SELECT e.email FROM (
    SELECT e.email FROM public.events e
    WHERE e.company_id=m.company_id AND e.distinct_id=m.user_key
      AND e.email IS NOT NULL AND e.email<>''
    ORDER BY e.event_time DESC LIMIT 5
 ) e WHERE NOT public.is_internal_email(e.email) LIMIT 1) old_label
 FROM sampled m
)
SELECT count(*) sample_size,
 count(*) FILTER(WHERE old_label IS NOT NULL) labels_with_existing_event,
 count(*) FILTER(WHERE old_label IS NOT NULL AND nullif(user_email,'') IS DISTINCT FROM old_label) mismatched_labels
FROM labels;
