# Customer module usage

`/customer` is a native Next.js App Router page. `CustomerDashboard` owns the
entire page in React and TypeScript, including the table, filters, month picker,
navigation, and definitions. It does not render a standalone HTML file or load
the legacy prototype runtime.

## Design

The page imports the existing global `app/prototype.css` through the root layout.
It reuses `po-user-table`, `po-company-detail`, `po-company-subtable`, search,
filters, pagination, dashboard-menu, and month-picker classes from the approved
modal design. `app/customer/customer.css` only adapts the page layout and numeric
column alignment. Parent rows are customers; expansion shows a bordered user
subtable. All rows start collapsed.

## Data

The typed fixture adapter preserves the Product Overview activity schedule,
company IDs, and user attribution. It never merges equal customer names.
Each current fixture company has one attributed user. The model supports several
users per customer, and aggregation tests cover that case without fabricating
memberships in the UI.

AP and AR sum their existing workflow event counts. Transactions combines
statement-upload and transaction-work activity, as the overview module does.
Sync remains separate. Counts are actions, not distinct documents. GST is null
and renders as a dash. Periods before the fixture starts are unavailable, not
zero. The reporting snapshot remains 4 October 2026.

Search selects matching customers without dropping their other users or changing
their totals. Integration and usage filters, stable sorting, and pagination are
applied after customer aggregation. Month filters include activity dates in the
selected months and cap the current month at the snapshot.

## Existing dashboards

`withCustomerNavigation` adds a link to the existing menu without changing the
reference HTML or analytics scripts. `installCustomerNavigation` extends keyboard
navigation to three entries and honors `/overview#retention`. Full document
navigation between the React page and the imperative prototype is deliberate:
the latter does not yet have a remount-safe lifecycle.

## Verification

After `npm ci`, run:

```sh
node --test tests/customer-usage.test.cjs
npm run typecheck
npm run build
```

The tests compare every customer event and per-module total against the existing
runtime fixture, including monthly ranges, multiple-user aggregation, unavailable
periods, search, filtering, sorting, pagination, and additive navigation.
No dependency versions or production data connections were changed.
