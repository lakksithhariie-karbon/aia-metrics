-- Jira dashboard query-plan optimization, REVIEW ONLY.
-- Prepared from read-only benchmarks on 2026-10-11. Do not apply until
-- explicitly approved. No data, ingestion, view, security or filter changes.
--
-- A function-local setting avoids nested-loop plans in the existing
-- dashboard reader's Core/Flow joins. It is scoped to this service-role-only
-- facade and its nested calls. The original SQL, snapshot guards, metric
-- definitions, historical filters and grants remain untouched.
--
-- Read-only baseline, unfiltered (execution milliseconds):
--   regular plan:      10261
--   nested loops off:   5528
-- Sprint 50 + AP: 1855 -> 1814 ms; selected counts match (87 open, 28 bugs).
-- The evidence v2 reader was marginally slower with this setting; do not
-- apply the optimization to that reader.
ALTER FUNCTION public.read_jira_delivery_dashboard_v1(
  bigint, text[], text[], text[], text[]
) SET enable_nestloop = off;

-- Rollback, if benchmarking or parity regresses, is a separately reviewed:
-- ALTER FUNCTION public.read_jira_delivery_dashboard_v1(
--   bigint, text[], text[], text[], text[]
-- ) RESET enable_nestloop;
