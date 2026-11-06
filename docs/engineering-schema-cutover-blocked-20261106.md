# BLOCKED: Engineering schema cutover, 2026-11-06

**Status:** NOT MIGRATED. Production remains on `jira`. Do not merge or deploy the cutover migration until the function-resolution issue is solved in a staging database.

## What was safely done

- Backed up the exact original definitions of all 35 Jira functions and the four public Jira delivery RPCs to `supabase/rollback/20261106_original_jira_function_definitions.sql`.
- Prepared (but did not successfully apply) an object-preserving schema rename migration and a lossless rollback.
- Temporarily deployed a dual-search-path `jira-sync` Edge Function (v13) and ran a normal incremental sync, ID 147. It finished at 2026-11-06 05:46:23 UTC with 51 issues upserted, 107 history rows, and **zero errors**.
- Attempted the guarded atomic schema migration. Every attempt was **rejected and rolled back automatically**, leaving Jira table OIDs, row counts, cron job, role configuration and existing schema unchanged. No successful Engineering schema migration was recorded.
- Restored the Edge Function to its byte-for-byte original GitHub `main` source (deployed as v14, JWT verification unchanged). Future scheduled jobs continue using `jira`.

## Blocker

During in-transaction SQL function replacement and subsequent runtime probes after renaming the schema, PostgreSQL cannot resolve the unqualified helper `_filter_sprint_matches(jsonb, integer[])` inside `_filter_cohort_row_matches`, even after setting the new search path and temporarily disabling creation-time function-body validation.

It is unclear whether this is related to command/snapshot cache visibility within a single transaction, a function-local search-path setting for the digit-prefixed schema name, or a different dependency issue. **Do not bypass the failing runtime probe on production.**

## Resolution prerequisites

1. Reproduce the schema rename/function rewrite against a separate test database with a fresh clone of the 35 Jira routines and dependency graph.
2. Validate unqualified helper lookup using actual function-local `search_path`, then run the dashboard RPC, evidence/drilldown, materialized refresh and sync functions.
3. Prepare a tested atomic migration and rollback, including exact object OID and row-count invariance and the existing `pg_cron` watchdog target.
4. Before a production retry, confirm a clean Jira sync, the four public RPC ACLs, and preserved source schema and role configuration.
5. Coordinate the switch with the two daily Jira sync jobs (02:30 and 12:30 UTC) and the five-minute snapshot watchdog.

**Strict exclusions:** No modifications to teammate-owned `feature_olap` or `product_source`, or to Product, Infra or Model. The pre-existing `jira` schema remains the production source of truth.

**WARNING:** Draft PR only. Never merge pending migrations with a known failing validation probe.
