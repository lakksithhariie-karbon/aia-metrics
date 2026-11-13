# Product migration, pre-cutover readiness and legacy dependency register
Updated: 8 November 2026. Scope: Supabase project `hdgbmcerogqfocyxdnpw` and draft PR #39.

## Evidence already passed

- **Product data:** All 58 numbered Product tables passed exact row-content comparisons against their 32 `public` + 26 `metrics_private` sources. The 53 smaller tables were compared with `EXCEPT ALL` in both directions; the five large tables were compared by primary key and full row JSONB, including detection of extra target keys. These checks were rerun successfully after the guarded shadow reconcilier updated 8 newly arrived events to a total of 552,876. Exact parity is **point-in-time** while legacy remains the primary writer, not a continuous invariant.
- **Reporting contracts:** All 105 public Product `read_*` functions have matching private argument lists, defaults, return types, volatility and SECURITY DEFINER settings. Service-role-only Overview, Retention and Companies canaries returned identical outputs to legacy. Product Analytics Usage `rows` and `pairs`, and Lifecycle output, also matched. Usage `meta.source` legitimately names the new source.
- **Database writer path:** A `SET LOCAL ROLE service_role`, `BEGIN … ROLLBACK` test exercised the private lease, an idempotent event upsert, retention rebuild, finish watermark and three safe prune functions. It completed with no exceptions and no persistent writes. **This is not an authenticated Edge request.**
- **Shadow scheduling:** Job #47 reconciles every 30 minutes; job #48 is scheduled for a daily full pass. #47 uses a fail-closed wrapper that throws if reconciliation returns anything other than success. The first independent scheduled execution of #48 still needs evidence.
- **Security and rollback:** All 58 private tables have RLS enabled. Private functions are not granted to anon/authenticated/service_role. The eight explicit `public.shadow_product_*` bridge RPCs and three read canaries are service-role-only. Public reader originals (12 backup parts), 47 writer/helper definitions (five backup parts), original eight cron commands and deployed `sync-incremental` v11 source (four files) are preserved under `supabase/rollback/`.

Reproducible tests:
- `supabase/tests/product_cutover_small_parity_part_{1,2,3}.sql`
- `supabase/tests/product_cutover_large_parity.sql`
- `supabase/tests/product_cutover_reader_contract_and_outputs.sql`
- `supabase/tests/product_shadow_writer_transaction_canary.sql`

## Unresolved legacy dependencies

| Surface | Existing behavior | Required resolution before retiring legacy |
| --- | --- | --- |
| Product hourly writer, cron #7 | Still invokes deployed `sync-incremental` v11 and legacy public RPCs | Authenticated end-to-end canary, then controlled canonical-writer switch with rollback |
| Product refresh crons #29, 39, 40, 41, 42, 45, 46 | Still execute `public` or `metrics_private` reporting refreshes | Reroute and test refresh work on the new schema; retain known-good schedules until safe |
| Two shadow crons #47, #48 | Continuously reconcile **legacy → new** | At writer cutover, disable or repurpose atomically. **Never keep legacy → new reconciliation running after the new schema becomes canonical**, or it may undo new writes |
| 105 public `read_*` RPCs | Used by Next.js Overview, Companies and Retention | The guarded **manual** proxy switch is staged in `supabase/cutover/PRODUCT_readers_manual_switch.sql`. It has NOT been applied; execute only after canonical writer is proven |
| `companies-dashboard` Edge function v2 | Reads `public.client_company`, `company_directory`, `events`, `export_watermarks` directly plus public RPCs | Migrate or retain a tested compatibility facade. Deployed function matches GitHub source; absence of recent logs does not prove no consumers |
| Model reporting | `04_model_schema.bill_extraction_reporting_v1` depends on `public.company_directory` | Preserve public compatibility data until the Model view and clients are moved, with separate owner approval |
| Private reporting FKs | Two `metrics_private` cache tables reference `public.product_snapshot` | Convert the cache consumers/FKs or preserve the legacy snapshot relation until safely unused |
| Legacy Model data flow | `aia_infra.bill_costs` and `aia_infra.companies` have triggers mirroring to `04_model_schema` | Migrate upstream writing to Model before retiring these legacy tables; parity of current data alone is insufficient |
| Infra legacy mirror | New `03_infra_schema.aws_costs` is more current than `aia_infra.aws_costs` | Audit and migrate any external legacy readers before removing old Infra data |
| Shared teammate dependencies | `feature_olap` and `product_source` must remain untouched | Treat as external contracts. Do not delete shared `public` objects or modify teammate schemas to force retirement |

The `public` schema itself is shared infrastructure and should **never** be dropped as a Product cleanup shortcut.

## Cutover readiness gates

1. **PASS:** Re-run all parity scripts immediately before cutover; every difference must be zero. After new writer takeover, compare canonical and compatibility copies according to the new direction of replication.
2. **BLOCKED:** Execute the deployed `sync-incremental-product-shadow` v1 through an authorized runtime with the existing managed `service_role` JWT and `CRON_SECRET`. A prepared runner, `scripts/product-shadow-authenticated-canary.mjs`, requires explicit `PRODUCT_SHADOW_CANARY_APPROVED=yes`, validates project/role and does not print secrets. It has **not** been executed here because the connected tool cannot safely invoke with production credentials. Record HTTP 2xx, `ok=true`, processed days, zero identity mismatches, refreshed metrics, shadow watermark and unchanged legacy watermark. Do not bypass credential controls.
3. **PENDING:** Verify application API routes and `companies-dashboard` compatibility while legacy is still active. Test Overview, Companies, Retention, historical/drilldown, Engineering, Infra and Model responses with realistic non-null inputs. Capture latency and production error baseline.
4. **PENDING:** Choose the final writer ownership and legacy-compatible data flow. Stage all cron and Edge changes as one rollback-able change set. The legacy→shadow reconciler must not conflict with the new canonical writer. Confirm source `public.company_directory` remains fresh for Model/teammate consumers, or route those consumers first.
5. **STAGED, NOT APPLIED:** After gates 1–4 pass, execute guarded reader proxy switch in a single transaction. It preserves 105 RPC signatures, defaults and timeouts; it refuses without explicit approved/writer-ready session flags. Original functions are available for rollback. Note that two Product Analytics functions and cross-team Features/OLAP require separate treatment.
6. **PENDING:** Execute controlled production deployment and smoke tests. Verify the original ingestion scheduler has switched intentionally, shadow jobs and caches are coherent, all dashboard APIs work, no RLS/grant regressions occur, and rollback steps have been rehearsed.
7. **PENDING:** Observe 48–72 hours of clean scheduled ingestion, metric freshness, zero unexplained parity drift, acceptable latency and no user-visible errors.
8. **PENDING:** Run a final dependency audit of code, functions, views, triggers, foreign keys, schedules and external consumers. Archive legacy data for the required retention period, then retire only individually confirmed-unused tables and routes. Preserve any compatibility exceptions.


## November 8 continuation: pre-cutover checks completed without switching production

- **Populated Product drill regression:** `supabase/tests/product_cutover_populated_drills.sql` passed all five source↔shadow reader comparisons. Source and shadow row counts were (1/1) Overview header, (12/12) Overview members, (1/1) Funnel header, (12/12) Funnel members and (377/377) Companies monthly breakdown. Every source-minus-shadow EXCEPT ALL difference was zero. These tests sample real published snapshot and monthly usage rows, rather than empty or default parameters.
- **Cross-domain service-role API check:** `supabase/tests/numbered_schema_cross_domain_service_role_smoke.sql` passed all seven probes for Engineering Jira, Infra AWS, Model extraction and analytics, and three Product shadow canary RPCs. These are SQL-level service-role RPC tests; they do **not** prove external HTTP routes or browser auth.
- **Model legacy directory dependency:** An isolated, read-only evaluation of the existing `04_model_schema.bill_extraction_reporting_v1` query with `01_product_schema.company_directory` instead of public company_directory produced **38,063 identical report rows** with zero differences in either direction. A manual, owner-and-writer-gated cutover and explicit rollback are staged under `supabase/cutover/MODEL_reporting_directory_manual_switch.sql` and `supabase/rollback/MODEL_reporting_directory_restore_public.sql`. Neither has been executed.
- **Live preflight:** `supabase/tests/product_cutover_live_preflight.sql` passed all seven database checks at `2026-11-08 08:38 UTC`, with 552,929 identical events, 58 RLS-enabled Product tables, 105 legacy+106 private reader inventory, service-role-only 11 canary/writer bridges, healthy original ingestion job #7 and shadow reconcile #47, and successful daily full #48. Use this immediately before cutover together with exact table parity tests.
- **Production deployment baseline:** Vercel reports the active `aia-metrics` production deployment as READY on main following Engineering PR #38. No runtime errors were returned within a queried 1-hour window, but this is not a substitute for routed HTTP/API smoke tests and can reflect low traffic.
- **No live routing changes:** The isolated shadow ingestion Edge v1 remains deployed but cannot be certified end-to-end until an **authorized authenticated runtime** executes `scripts/product-shadow-authenticated-canary.mjs` with existing managed credentials. PR #39 stays draft; legacy ingestion and legacy-to-new scheduled reconciliation still own the production path.

For a **new project**, controlled read-only integration is possible now using the existing service-role-only `public.read_product_shadow_*_canary` RPCs from a protected server. Never put a service-role credential in client-side code, and do not assume new Product tables are directly exposed through PostgREST. Full live writer ownership and retirement remain separate pending gates.

## Acceptance standard

Do **not** sign off solely because tables match or PR CI is green. A final “SAFE TO RETIRE LEGACY” requires an authenticated Edge canary, production writer and read cutover, verified cross-schema workflows, the 48–72-hour stability window and zero unhandled legacy dependencies. Otherwise the verdict remains “NOT YET SAFE.” Draft PR #39 must stay unmerged until ready for production.
