# Companies module usage

`/customer` is a native Next.js App Router page that renders the **Companies**
reporting surface from live Supabase data. `CompaniesDashboard` owns the page
in React and TypeScript: table, filters, month picker, navigation, breakdown
modal, and definitions. The route stays `/customer`; visible wording is
**Companies**. There is no `/companies` route and no redirect.

## Design

The page imports the global `app/prototype.css` through the root layout and
reuses `po-user-table`, `po-company-detail`, `po-company-subtable`, search,
filters, pagination, dashboard-menu, and month-picker classes from the approved
v2 system. `app/customer/customer.css` adds only the module-count buttons and
the breakdown modal. Parent rows are companies keyed by stable company ID;
expansion shows observed users; clicking a module number (never the row or
company name) opens the breakdown modal scoped to that company/user/module.

## Data

```
React Companies page
→ Next.js POST /api/companies (forwards Vercel OIDC, 10s timeout, fails closed)
→ Supabase Edge Function `companies-dashboard` (verifies Vercel issuer,
  audience and project id, then reads with its server-side service role)
→ public.client_company + public.company_directory + public.events
```

The browser only receives the bounded page/modal JSON. No Supabase secret,
service_role key, or raw-event access reaches the browser bundle. There is no
fixture fallback: bridge failures render an honest error state.

Module mapping is centralized in `supabase/companies-live.sql`
(`company_module_for` / `company_subtype_for` / `company_items_for`, plus the
`read_companies_usage` / `read_companies_breakdown` aggregates). Counts are
event occurrences; item volume (`items_count`, `itemsCount`,
`transactionCount`) is summed separately and rendered as unavailable (never
zero) when uninstrumented. `lib/companies/modules.ts` is the tested TypeScript
twin; `testdata/companies-module-vectors.json` is replayed against both sides
by `scripts/verify-companies-bridge.mjs`.

Company identity is `company_id` (never the name). Display priority:
`company_directory.company_name` → latest usable event company name
(`read_company_names`, placeholders denied) → raw ID — event data carries no
other usable names, and equal names are never merged. Nested users are ALL
observed `(company_id, distinct_id)` pairs (`read_company_users`), including
users with zero mapped activity in the period (zero-filled); the latest
non-empty non-internal email is shown. Empty identities with mapped activity
are preserved as Unattributed activity so company totals always equal
attributed users plus unattributed activity.
Internal staff activity (`public.is_internal_email`, same predicate in the
usage reader, the breakdown reader, email search, and user labels) is excluded
consistently. Integration comes from the latest successful `Integration status`
event.
Warehouse history starts March 2026 (Asia/Kolkata); earlier months render as
unavailable, not zero. Source freshness comes from `export_watermarks`.

## Verification

After `npm ci`, run:

```sh
node --test tests/companies-live.test.cjs
npm run typecheck
npm run build
```

Then `node scripts/verify-companies-bridge.mjs` with server-side
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` in the environment, plus the
manual reconciliation check (table count = modal event sum; company total =
users + unattributed) before shipping.
