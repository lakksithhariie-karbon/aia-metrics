# Engineering & Delivery Jira-backed preview

**Status, 10 October 2026:** GitHub branch ready for hosted preview. The latest Next.js/TypeScript/contract build is green in GitHub Actions. **No production merge.** Vercel returned the Hobby team's 100 API deployments/day limit, so a new hosted preview cannot yet be claimed.

## Architecture

- GitHub is the only source: `lakksithhariie-karbon/aia-metrics`.
- Existing Supabase project: `hdgbmcerogqfocyxdnpw`. Existing Edge Function `jira-sync` v12 and its scheduled jobs are unchanged by dashboard work.
- Existing audited Jira schema and view contracts are retained.
- Next.js `app/delivery/page.tsx` calls `lib/delivery/server.ts` with a Vercel **server-only** service-role credential.
- `public.read_jira_delivery_dashboard_v1` combines Jira's verified core, flow, and quality readers into a ~30–45 KB dashboard response, without issue-level drill arrays.
- `app/api/delivery/evidence/route.ts` accepts a validated snapshot ID, filter scope, cohort and offset; `public.read_jira_delivery_evidence_v1` returns at most 50 matching issues per page. The client uses 40-item pages.
- Both new public RPC facades are granted only to `service_role`, not `anon` or `authenticated`. No Jira API token is stored in GitHub or sent to the browser.
- Page geometry, navigation and card style reuse Product Metrics (1560px, 12 columns, 24px gaps).

## Cards, reports and sources

| UI | Existing Jira source used |
| --- | --- |
| Sprint commitment, mid-sprint created, delivered, throughput | `jira.get_filtered_dashboard_core_submodule`, validated sprint-discipline and throughput |
| Committed but not done | Same sprint commitment denominator plus separately audited issue evidence |
| Stale, stale+blocked, L1, QA queue, blocked | Filtered cohort n and `jira.get_filtered_dashboard_flow_submodule` |
| Open bugs, reopened, QA rejection, bug resolution, QA turnaround | `jira.get_filtered_dashboard_quality_submodule`, bug health, published cohort details |
| Code Review | **Selected sprint's stage median** and real per-issue accumulated hours from status history, not the active-only legacy Code Review cohort |
| Work in flight | `flow.wip_by_status`, reconciled to the open-work cohort |
| Planned vs done | Four published sprint-discipline and throughput rows |
| Issue types by sprint | Direct/non-subtask sprint rows, grouped with the exact same removal cutoff and filters as sprint scope |
| Flow health | Seven stage dwell groups for the selected/active sprint |
| Open bug aging | Bug health age histogram (sum equals open bugs) |
| Backlog trend | Existing published weekly open-issue series |

All 15 cards have source definitions. Coherent cohort/status/type/code-review selections have paginated issue evidence; percentage metrics based on multiple decisions display the number of underlying affected issues separately from event-cycle denominators.

## Filters and reconciliation

Five supported filters: sprint (the four published SPEND sprints), module, sub-module, severity and assignee. Untagged module/sub-module/severity options preserve missing-field populations. Applied filters are encoded in the URL, not local arithmetic, and propagated to all core, flow, quality and evidence readers.

The source facade **fails closed** if the latest Jira ingestion ID (including in-progress or partially failed runs) differs from the published snapshot. The dashboard will show an explicit unavailable state during sync/publication rather than labeling partially updated current-state rows as the previous clean snapshot. The existing five-minute watchdog normally rebuilds snapshots in ~5 minutes after a clean sync. No extra refresh infrastructure was added.

Jira-issue totals are reconciled between the independently calculated core and flow sources for open, bugs, stale, blocked, stale+blocked and QA. Sprint issue-type counts must equal the matching sprint's scope. Bug-age buckets must sum to open bugs. Evidence requires the same snapshot ID; historical Code Review evidence independently verifies both count and median from issue field transitions.

## Snapshot-93 audit examples

- All work: **808** open, **304** open bugs, **578** stale, **41** blocked, **84** QA queue.
- Sprint 50: scope **998**, completed now **459**, committed **761**, committed delivered **354**, resulting completion of commitments **46.5%**.
- Sprint 50 + module AP: **93** open and **33** open bugs; sprint scope **219**, completed **126**.
- Code Review: Sprint 50 **183** measured issues, **4.2 h** median; Sprint 49 **210**, **15.6 h** median. AP-only samples match the corresponding flow-stage populations.
- Source still holds **6,931 raw and derived issues** plus **71,307 field-history records**. The deleted Jira records remain in audit storage but do not appear in the current-state dashboard.
- Published sync: **93**. This is a checked source snapshot, not a hardcoded dashboard fixture.

## Verification

- `npm run build` runs existing Product Overview and Companies contract guards plus Engineering shell, Jira foundation and Jira reporting guards; TypeScript builds on Node 24 in GitHub Actions.
- Use `supabase/tests/jira_delivery_dashboard_contract.sql` for repeatable read-only database validation, without changing the issue data.
- A live, unauthenticated browser click-through of the **new** branch is still pending a hosted Vercel preview. Do not claim otherwise.
- Beware that the user's **production** Vercel site is public by design. Publishing this Engineering route to production would also expose Jira issue summaries to anyone visiting the site; review the shareholder distribution implications before merge.

## Review and release

1. Wait for the Vercel deployment quota to reset, then deploy this GitHub branch to **preview**, not production.
2. Test initial load, five URL filters, 15 cards, six reports, modal paging, card definitions, history warning, external Jira links and mobile layout in the hosted preview.
3. Review the draft PR and preview with the user. **Do not merge to `main` until explicitly approved.**
