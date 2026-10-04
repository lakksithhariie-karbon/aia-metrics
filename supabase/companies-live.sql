-- Companies live-usage data plane for the `companies-dashboard` Supabase Edge Function.
--
-- Canonical module mapping (single runtime implementation). The TypeScript twin
-- `lib/companies/modules.ts` mirrors this logic for unit tests; any change here
-- must update that file, `testdata/companies-module-vectors.json`, and the
-- conformance script `scripts/verify-companies-bridge.mjs`.
--
-- Security: service_role is server-only (used inside the OIDC-gated Edge
-- Function). RLS policies are untouched. NOTHING is granted to anon or
-- authenticated, so no browser client can call these functions or read the
-- underlying tables through them.
--
-- Top-level module numbers are EVENT OCCURRENCES, never unique documents.
-- Affected-item volume (items_count / itemsCount / transactionCount) is summed
-- separately and exposed alongside event counts, never mixed into them.

-- 1) company_directory must be readable server-side (service_role already reads
--    client_company and events). Read-only; RLS stays enabled.
GRANT SELECT ON public.company_directory TO service_role;

-- 2) Canonical classifier: event_name + properties -> module (or NULL = unmapped).
CREATE OR REPLACE FUNCTION public.company_module_for(
  p_event_name text,
  p_properties jsonb
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN (p_event_name IN ('Upload', 'Delete', 'Download')
          AND lower(p_properties ->> 'type') = 'bill')
      OR (p_event_name = 'Entity Created'
          AND lower(p_properties ->> 'entityType') = 'bill')
      OR p_event_name IN ('Invoice Bulk Edited', 'Vendor Mismatch Resolved')
      THEN 'ap'
    WHEN (p_event_name IN ('Upload', 'Download')
          AND lower(p_properties ->> 'type') = 'invoice')
      OR (p_event_name = 'Entity Created'
          AND lower(p_properties ->> 'entityType') = 'invoice')
      OR p_event_name IN ('Invoice Created', 'Download-Inv', 'Preview')
      THEN 'ar'
    WHEN (p_event_name IN ('Upload', 'Download')
          AND lower(p_properties ->> 'type') = 'statement')
      OR p_event_name IN ('Transaction Ledger Updated', 'Transaction Status',
                          'Transaction Type Updated',
                          'Transaction Configuration Edited')
      THEN 'transactions'
    WHEN (p_event_name = 'Upload'
          AND lower(p_properties ->> 'type') IN ('gstr2b', 'purchase_register'))
      OR p_event_name = 'Recon Processed'
      OR (p_event_name = 'Download'
          AND lower(p_properties ->> 'type') = 'reconciled_excel')
      OR (p_event_name = 'Export'
          AND lower(p_properties ->> 'type') = 'gst_reconciliation')
      THEN 'gst'
    WHEN p_event_name = 'Accounting Sync'
      THEN 'sync'
    ELSE NULL
  END
$$;

-- 3) Subtype / property split for the breakdown modal (NULL = not applicable).
CREATE OR REPLACE FUNCTION public.company_subtype_for(
  p_event_name text,
  p_properties jsonb
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_event_name IN ('Upload', 'Delete', 'Download', 'Download-Inv',
                          'Export', 'Preview')
      THEN NULLIF(btrim(p_properties ->> 'type'), '')
    WHEN p_event_name = 'Entity Created'
      THEN NULLIF(btrim(p_properties ->> 'entityType'), '')
    WHEN p_event_name IN ('Transaction Ledger Updated', 'Transaction Type Updated')
      THEN NULLIF(
             concat_ws(' → ',
               NULLIF(btrim(p_properties ->> 'from'), ''),
               NULLIF(btrim(p_properties ->> 'to'), '')),
             '')
    WHEN p_event_name = 'Transaction Configuration Edited'
      THEN NULLIF(btrim(p_properties ->> 'configField'), '')
    WHEN p_event_name = 'Vendor Mismatch Resolved'
      THEN NULLIF(btrim(p_properties ->> 'resolutionType'), '')
    WHEN p_event_name = 'Accounting Sync'
      THEN (SELECT string_agg(value, ', ')
            FROM jsonb_array_elements_text(p_properties -> 'sync_items') AS value
            WHERE NULLIF(btrim(value), '') IS NOT NULL)
    ELSE NULL
  END
$$;

-- 4) Instrumented affected-item volume for one event (NULL = not instrumented).
CREATE OR REPLACE FUNCTION public.company_items_for(
  p_event_name text,
  p_properties jsonb
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_event_name = 'Accounting Sync'
         AND jsonb_typeof(p_properties -> 'items_count') = 'number'
      THEN (p_properties ->> 'items_count')::bigint
    WHEN p_event_name = 'Transaction Status'
         AND jsonb_typeof(p_properties -> 'itemsCount') = 'number'
      THEN (p_properties ->> 'itemsCount')::bigint
    WHEN p_event_name IN ('Transaction Ledger Updated', 'Transaction Type Updated')
         AND jsonb_typeof(p_properties -> 'transactionCount') = 'number'
      THEN (p_properties ->> 'transactionCount')::bigint
    ELSE NULL
  END
$$;

-- 5) Population aggregate: one row per (company, user, module) with event and
--    item totals. user_key is NULL for unattributed activity (no usable
--    distinct_id). user_email is the latest non-empty email observed for that
--    company + user. Internal staff activity (public.is_internal_email) is
--    excluded consistently here, in the breakdown reader, and in email search
--    (which derives from this filtered population). Companies with no
--    qualifying events in range return no rows; the Edge Function zero-fills
--    them from client_company.
CREATE OR REPLACE FUNCTION public.read_companies_usage(
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL
)
RETURNS TABLE (
  company_id text,
  user_key text,
  user_email text,
  module text,
  events bigint,
  items bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH bounds AS (
    SELECT (p_from::text || 'T00:00:00+05:30')::timestamptz AS start_at,
           ((p_to + 1)::text || 'T00:00:00+05:30')::timestamptz AS end_at
  ),
  classified AS (
    SELECT e.company_id,
           NULLIF(btrim(e.distinct_id), '') AS user_key,
           e.email,
           e.event_time,
           public.company_module_for(e.event_name,
             COALESCE(e.properties, '{}'::jsonb)) AS module,
           public.company_items_for(e.event_name,
             COALESCE(e.properties, '{}'::jsonb)) AS items
    FROM public.events e
    JOIN public.client_company c ON c.company_id = e.company_id
    CROSS JOIN bounds
    WHERE (p_from IS NULL OR e.event_time >= bounds.start_at)
      AND (p_to IS NULL OR e.event_time < bounds.end_at)
      AND NOT public.is_internal_email(e.email)
  )
  SELECT classified.company_id,
         classified.user_key,
         (ARRAY_AGG(classified.email ORDER BY classified.event_time DESC)
            FILTER (WHERE NULLIF(btrim(classified.email), '') IS NOT NULL))[1]
            AS user_email,
         classified.module,
         COUNT(*) AS events,
         SUM(classified.items) AS items
  FROM classified
  WHERE classified.module IS NOT NULL
  GROUP BY classified.company_id, classified.user_key, classified.module
$$;

-- 6) Module breakdown for one company (optionally one user): per
--    (event, subtype, status) counts, separately summed instrumented items,
--    instrumented-row count (to render unavailable as unavailable, not zero),
--    and latest activity.
CREATE OR REPLACE FUNCTION public.read_companies_breakdown(
  p_company_id text,
  p_module text,
  p_user_key text DEFAULT NULL,
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL
)
RETURNS TABLE (
  event text,
  subtype text,
  status text,
  events bigint,
  items bigint,
  instrumented bigint,
  latest_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH bounds AS (
    SELECT (p_from::text || 'T00:00:00+05:30')::timestamptz AS start_at,
           ((p_to + 1)::text || 'T00:00:00+05:30')::timestamptz AS end_at
  ),
  classified AS (
    SELECT e.event_name AS event,
           public.company_subtype_for(e.event_name,
             COALESCE(e.properties, '{}'::jsonb)) AS subtype,
           NULLIF(btrim(COALESCE(e.properties, '{}'::jsonb) ->> 'status'), '')
             AS status,
           public.company_items_for(e.event_name,
             COALESCE(e.properties, '{}'::jsonb)) AS items,
           e.event_time
    FROM public.events e
    CROSS JOIN bounds
    WHERE e.company_id = p_company_id
      AND NOT public.is_internal_email(e.email)
      AND (p_user_key IS NULL
           OR NULLIF(btrim(e.distinct_id), '') IS NOT DISTINCT FROM
              NULLIF(btrim(p_user_key), ''))
      AND (p_from IS NULL OR e.event_time >= bounds.start_at)
      AND (p_to IS NULL OR e.event_time < bounds.end_at)
      AND public.company_module_for(e.event_name,
            COALESCE(e.properties, '{}'::jsonb)) = p_module
  )
  SELECT classified.event,
         classified.subtype,
         classified.status,
         COUNT(*) AS events,
         SUM(classified.items) AS items,
         COUNT(classified.items) AS instrumented,
         MAX(classified.event_time) AS latest_at
  FROM classified
  GROUP BY classified.event, classified.subtype, classified.status
  ORDER BY COUNT(*) DESC, classified.event ASC
$$;

-- 7) Observed company users (membership, NOT module activity): every real
--    (company_id, distinct_id) pair ever observed in public.events for a
--    client company, after the same staff exclusion. Users with zero mapped
--    module activity in a selected period still appear (zero-filled by the
--    Edge Function). user_email is the latest usable non-internal email.
--    Bounded: one row per observed pair (~thousands, not events).
CREATE OR REPLACE FUNCTION public.read_company_users()
RETURNS TABLE (
  company_id text,
  user_key text,
  user_email text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT e.company_id,
         NULLIF(btrim(e.distinct_id), '') AS user_key,
         (ARRAY_AGG(e.email ORDER BY e.event_time DESC)
            FILTER (WHERE NULLIF(btrim(e.email), '') IS NOT NULL
                    AND NOT public.is_internal_email(e.email)))[1]
            AS user_email
  FROM public.events e
  JOIN public.client_company c ON c.company_id = e.company_id
  WHERE NULLIF(btrim(e.distinct_id), '') IS NOT NULL
    AND NOT public.is_internal_email(e.email)
  GROUP BY e.company_id, NULLIF(btrim(e.distinct_id), '')
$$;

-- 8) Usable company names observed in event data. Company Created/Updated
--    events carry free-text companyName values mixing real names with
--    placeholders; only non-denied values count as usable. The denied list is
--    intentionally tight and documented; adjust it with product as needed.
CREATE OR REPLACE FUNCTION public.company_usable_name(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(p_raw), '') IS NULL THEN NULL
    WHEN lower(btrim(p_raw)) IN (
      'abc', 'dummy', 'na', 'n/a', 'test', 'testing', 'demo', 'xyz',
      'delete company') THEN NULL
    ELSE btrim(p_raw)
  END
$$;

-- 9) Latest usable event company name per client company (middle tier of the
--    display-name fallback). Pass a company id for one row (breakdown modal)
--    or NULL for all companies that have any usable name (list page).
CREATE OR REPLACE FUNCTION public.read_company_names(p_company_id text DEFAULT NULL)
RETURNS TABLE (
  company_id text,
  event_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.company_id,
    (SELECT public.company_usable_name(p.properties ->> 'companyName')
     FROM public.events p
     WHERE p.company_id = c.company_id
       AND public.company_usable_name(p.properties ->> 'companyName') IS NOT NULL
     ORDER BY p.event_time DESC
     LIMIT 1) AS event_name
  FROM public.client_company c
  WHERE (p_company_id IS NULL OR c.company_id = p_company_id)
$$;

-- 10) Lock down execution: server roles only. Anon/authenticated get nothing,
--    so these functions are unreachable from any browser client.
REVOKE ALL ON FUNCTION public.company_module_for(text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.company_subtype_for(text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.company_items_for(text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.read_companies_usage(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.read_companies_breakdown(text, text, text, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.read_company_users() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.company_usable_name(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.read_company_names(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.company_module_for(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.company_subtype_for(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.company_items_for(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_companies_usage(date, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_companies_breakdown(text, text, text, date, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_company_users() TO service_role;
GRANT EXECUTE ON FUNCTION public.company_usable_name(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_company_names(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_companies_usage(date, date) TO product_metrics_fetcher;
GRANT EXECUTE ON FUNCTION public.read_companies_breakdown(text, text, text, date, date) TO product_metrics_fetcher;
GRANT EXECUTE ON FUNCTION public.read_company_users() TO product_metrics_fetcher;
GRANT EXECUTE ON FUNCTION public.read_company_names(text) TO product_metrics_fetcher;
