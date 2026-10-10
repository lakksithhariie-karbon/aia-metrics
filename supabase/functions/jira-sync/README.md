# Jira foundation (GitHub-owned)

This directory is the authoritative source for the **existing** Supabase `jira-sync` Edge Function, imported from the live deployed version 10 (10 October 2026). GitLab is not part of the development or deployment process.

## Deployment target

- GitHub repository: `lakksithhariie-karbon/aia-metrics`
- Supabase project: `hdgbmcerogqfocyxdnpw`
- Function: `jira-sync`
- Existing scheduled jobs: `jira-sync-0230utc` and `jira-sync-1230utc`
- This version is **staged in GitHub**; it is not automatically deployed when the app preview builds.

## Security requirements

The function requires `POST` with a **Supabase gateway-verified JWT whose role is `service_role`** before executing any database or Jira work. **Always deploy with `verify_jwt=true`.** The existing pg_cron jobs already supply the service-role JWT stored in Supabase Vault. The `jira-sync` handler decodes the role only after gateway signature verification; it does not accept ordinary user JWTs or unauthenticated requests. Do not compare the JWT to the built-in `SUPABASE_SERVICE_ROLE_KEY`: valid legacy Vault service-role JWTs may differ from that environment value.

Do not commit credentials, Jira tokens, vault values or API headers to GitHub, public variables or logs. Jira credentials remain Supabase Edge Function secrets.

## Data integrity

The matching migration in `supabase/migrations/20261010_jira_reference_project_rename_fix.sql` deterministically selects one latest project name per Jira project key. Historical raw issues can retain the prior project name; the current reference table should have a single current name.

This migration changes only the reference refresh function. The snapshot watchdog still publishes only after an error-free run. Verify a clean run and matching snapshot watermark before switching dashboard readers.

## Verification & rollback

Run `node scripts/verify-jira-foundation.mjs` for static checks. After database migration, validate `jira.refresh_reference_tables()`, `jira.sync_log`, the dashboard snapshot ID and reference-table row counts. Compare old/new reporting readers on the same recorded population before replacing views.

Rollback: redeploy the prior Supabase function version if necessary. Store the existing SQL definition as part of the migration/review history. Do not revert raw issue history or delete reporting materializations.
