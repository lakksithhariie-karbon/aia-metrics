# AI Services Bill Extraction: verified preview reader

The `/ai-services` route now reads `aia_infra.bill_extraction_reporting_v1` through `public.read_ai_bill_extraction_v1`, a restricted, **read-only** Supabase RPC (`EXECUTE` granted to `service_role` only; `anon` and `authenticated` denied). `security definer` runs with an empty search path, and the underlying reporting view remains private. This migration has already been applied to the live Supabase project as `20261101185848`.

The Next.js handler `/api/ai-services/report` runs server-side in Vercel Preview, using existing server-only `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` environment variables. `VERCEL_ENV=production` explicitly denies this route until production authorization has been designed and reviewed. Preview deployment protection remains responsible for authenticating browser access. Never leak those variables to the client.

`GET` returns aggregated KPI, monthly, document, review, legibility, company and exception populations from the same selected scope. `POST` returns exactly one page of 10 underlying predictions for the chosen drill, sorted on the server; no full record population is shipped to the browser. Date ranges represent UTC calendar months and default to six completed months. Company classification defaults to `verified_customer`.

Unknown cost or latency is **never converted to zero**. Recorded cost is not guaranteed to represent all historical spend, and currency and latency units remain undocumented. Review state is a current snapshot, not extraction success/failure. The UI reports the reporting view's `loaded_at` watermark. `company_scope` is explicit for test/unverified populations. The mock fixture remains in `testdata/` for offline regression tests and is not imported by the UI.

Verification: source-vs-dashboard population reconciliation, aggregate-to-month/document/review/company equality, anon-denied/service-role-allowed ACL checks, `npm run build`, and preview route/drill-through checks. Before production, add application authentication and authorization rather than removing the Preview-only guard.
