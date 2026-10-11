# Jira foundation (GitHub-owned)

This directory is the authoritative source for the **existing** Supabase `jira-sync` Edge Function, imported from the live deployed version 10 (10 October 2026). GitLab is not part of the development or deployment process.

## Deployment target

- GitHub repository: `lakksithhariie-karbon/aia-metrics`
- Supabase project: `hdgbmcerogqfocyxdnpw`
- Function: `jira-sync`
- Existing scheduled jobs: `jira-sync-0230utc` and `jira-sync-1230utc`
- GitHub is the source of truth. Supabase function deployment and SQL migrations are applied separately from Vercel preview builds.
- **Deployed to shared Supabase on 2026-10-10:** Edge Function version **12** (`verify_jwt=true`), and migration `jira_reference_project_rename_fix_20261010`.

## Security requirements

The function requires `POST` with a **Supabase gateway-verified JWT whose role is `service_role`** before executing any database or Jira work. **Always deploy with `verify_jwt=true`.** The existing pg_cron jobs already supply the service-role JWT stored in Supabase Vault. The `jira-sync` handler decodes the role only after gateway signature verification; it does not accept ordinary user JWTs or unauthenticated requests. Do not compare the JWT to the built-in `SUPABASE_SERVICE_ROLE_KEY`: valid legacy Vault service-role JWTs may differ from that environment value.

Do not commit credentials, Jira tokens, vault values or API headers to GitHub, public variables or logs. Jira credentials remain Supabase Edge Function secrets.

## Data integrity

The matching migration in `supabase/migrations/20261010_jira_reference_project_rename_fix.sql` deterministically selects one latest project name per Jira project key. Historical raw issues can retain the prior project name; the current reference table should have a single current name.

This migration changes only the reference refresh function. The snapshot watchdog still publishes only after an error-free run. Verify a clean run and matching snapshot watermark before switching dashboard readers.

## Verified recovery, 2026-10-10

The restoration was validated against the **existing live Supabase** project without modifying raw Jira history.

| Check | Actual result |
| --- | --- |
| Unauthenticated POST | 401, refused by Supabase Edge gateway |
| Authorized pg_cron-equivalent POST | 200, `ok: true` |
| First clean run after repair | Sync **93**, 2 Jira issues synchronized, **0 errors** |
| Reference table | Project `SPEND` resolved deterministically to latest name `AiA` |
| Dashboard snapshot watchdog | Job 15 succeeded, refreshed from sync **89** to **93** |
| Snapshot publication | `refreshed_sync_id=93`, latest clean `sync_log.id=93` |
| Source consistency | 6,931 raw records = 6,931 derived records, no missing issue IDs |
| Sprint membership consistency | 15,586 links, 0 missing issue/sprint references |
| Field history | 71,307 retained change records |
| Snapshot/source parity | Open work **819/819**, open bugs **305/305**, QA queue **84/84** |

The existing watchdog requires a completed, zero-error ingestion before publication. Historical full refreshes normally take 4–6 minutes, which exceeds the ad-hoc SQL tool's two-minute statement timeout; the scheduled job uses 15 minutes. Do not interpret a timed-out ad-hoc refresh as a publishing failure unless the watchdog also fails.

**Scope boundary:** This repair fixes authentication, the project rename/reference upsert, and snapshot freshness. Separate reporting-model findings, such as `jira.v_sprint_discipline.done_now` and deleted records in legacy open-work views, still require separately tested view changes. Do not imply those unrelated metric definitions were changed here.

## Verification & rollback

Run `node scripts/verify-jira-foundation.mjs` for static checks. After database migration, validate `jira.refresh_reference_tables()`, `jira.sync_log`, the dashboard snapshot ID and reference-table row counts. Compare old/new reporting readers on the same recorded population before replacing views.

Rollback: preserve the current version-12 deployment and migration as the default. Older function version 10 lacked authenticated request enforcement and should **not** be redeployed without compensating protection. If an incident requires rollback, first secure the endpoint and verify the cron credential path. Revert reporting SQL only through a reviewed migration; the previous reference SQL had a known failure. Never delete raw Jira history or materialized reporting rows as a rollback.
