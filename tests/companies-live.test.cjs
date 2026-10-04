/* Companies live-data tests. Run: node --test tests/companies-live.test.cjs
 * Covers the required contract against the canonical TypeScript twin
 * (lib/companies/modules.ts) and the shipped file/route surface. SQL/runtime
 * equivalence is proven separately by scripts/verify-companies-bridge.cjs
 * against the deployed bridge plus the reconciliation check in the report. */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const root = path.resolve(__dirname, '..');
const cache = new Map();
function load(relative) {
  const file = path.resolve(root, relative);
  if (cache.has(file)) return cache.get(file);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  });
  const module = { exports: {} };
  new Function('require', 'module', 'exports', output.outputText)(
    name => name.startsWith('.') ? load(path.relative(root, path.resolve(path.dirname(file), name + '.ts'))) : require(name),
    module, module.exports);
  cache.set(file, module.exports);
  return module.exports;
}
const modules = load('lib/companies/modules.ts');
const vectors = JSON.parse(fs.readFileSync(path.join(root, 'testdata/companies-module-vectors.json'), 'utf8'));
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');

const ev = (event_name, properties = {}, extra = {}) =>
  ({ event_name, properties, event_time: '2026-09-10T10:00:00+00:00', ...extra });

test('1. module classification matches the shared vectors', () => {
  assert(vectors.length > 30, 'vectors cover every module branch');
  for (const vector of vectors) {
    assert.equal(modules.moduleFor(vector.event_name, vector.properties), vector.module,
      `${vector.event_name} ${JSON.stringify(vector.properties)}`);
    assert.equal(modules.subtypeFor(vector.event_name, vector.properties), vector.subtype,
      `subtype ${vector.event_name} ${JSON.stringify(vector.properties)}`);
    assert.equal(modules.itemsFor(vector.event_name, vector.properties), vector.items,
      `items ${vector.event_name} ${JSON.stringify(vector.properties)}`);
  }
});

test('staff activity is excluded from company attribution', () => {
  assert(modules.isInternalEmail('analyst@karboncard.com'));
  assert(modules.isInternalEmail('Ops <ANALYST@Korefi.AI>'));
  assert(modules.isInternalEmail('someone@sub.aiaccountant.com'));
  assert(!modules.isInternalEmail('client@example.com'));
  assert(!modules.isInternalEmail(''));
  assert(!modules.isInternalEmail(null));
  const rows = modules.aggregateEvents([
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u1', email: 'staff@karboncard.com' }),
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u2', email: 'client@example.com' }),
  ]);
  assert.equal(rows[0].totals.ap, 1, 'internal event is not counted');
  assert.equal(rows[0].users.length, 1, 'internal user is not attributed');
  assert.equal(rows[0].users[0].email, 'client@example.com');
});

test('edge list honors direction for name sort with id tie-break', () => {
  const edge = read('supabase/functions/companies-dashboard/index.ts');
  assert(!/const usage =/.test(edge), 'no shadowed usage binding remains');
  assert(edge.includes('usageFilter'), 'usage filter has its own binding');
  assert(edge.includes('usageByCompany'), 'usage aggregate has its own binding');
  assert(/if \(sort === "name"\) return [^;]*\* sign;/.test(edge), 'name sort applies direction');
  assert(!edge.includes('.ilike("email"'), 'email search derives from the filtered aggregate, not raw events');
  assert(edge.includes('read_company_users'), 'membership comes from the observed-users aggregate');
  const rows = [
    { id: 'b', name: 'B Co', users: [], totals: modules.emptyTotals() },
    { id: 'a', name: 'A Co', users: [], totals: modules.emptyTotals() },
  ];
  assert.deepEqual(modules.sortRows(rows, 'name', 'desc').map(row => row.id), ['b', 'a']);
});

test('SQL readers exclude internal staff activity in both paths', () => {
  const sql = read('supabase/companies-live.sql');
  const usageBody = sql.slice(sql.indexOf('read_companies_usage'), sql.indexOf('read_companies_breakdown'));
  const breakdownBody = sql.slice(sql.indexOf('read_companies_breakdown'));
  // Hot paths use the inlined C-level twin (per-row plpgsql dispatch blew the
  // statement timeout); the low-volume breakdown calls the function directly.
  assert(usageBody.includes("'%.karboncard.com'"), 'usage reader excludes staff via inlined domains');
  assert(usageBody.includes('has_email'), 'usage reader keeps the empty-email rule');
  assert(breakdownBody.includes('NOT public.is_internal_email(e.email)'), 'breakdown reader excludes staff');
});

test('12. GST event mapping covers all five first-pass branches', () => {
  const gst = vectors.filter(v => v.module === 'gst');
  assert(gst.some(v => v.event_name === 'Upload' && v.properties.type === 'gstr2b'));
  assert(gst.some(v => v.event_name === 'Upload' && v.properties.type === 'purchase_register'));
  assert(gst.some(v => v.event_name === 'Recon Processed'));
  assert(gst.some(v => v.event_name === 'Download' && v.properties.type === 'reconciled_excel'));
  assert(gst.some(v => v.event_name === 'Export' && v.properties.type === 'gst_reconciliation'));
});

test('13. Sync keeps event count distinct from items_count', () => {
  const rows = modules.aggregateEvents([
    ev('Accounting Sync', { sync_items: ['bills'], items_count: 2 }, { company_id: 'c1', distinct_id: 'u1' }),
    ev('Accounting Sync', { sync_items: ['transactions'], items_count: 3 }, { company_id: 'c1', distinct_id: 'u1' }),
    ev('Accounting Sync', {}, { company_id: 'c1', distinct_id: 'u1' }),
  ]);
  assert.equal(rows[0].totals.sync, 3);
  assert.equal(rows[0].users[0].totals.sync, 3);
});

test('14. transaction event count stays distinct from transactionCount', () => {
  const rows = modules.aggregateEvents([
    ev('Transaction Type Updated', { transactionCount: 3 }, { company_id: 'c1', distinct_id: 'u1' }),
    ev('Transaction Status', { itemsCount: 7 }, { company_id: 'c1', distinct_id: 'u1' }),
    ev('Transaction Ledger Updated', { status: 'Success' }, { company_id: 'c1', distinct_id: 'u1' }),
  ]);
  assert.equal(rows[0].totals.transactions, 3);
  assert.equal(modules.itemsFor('Transaction Type Updated', { transactionCount: 3 }), 3);
  assert.equal(modules.itemsFor('Transaction Status', { itemsCount: 7 }), 7);
  assert.equal(modules.itemsFor('Transaction Ledger Updated', { status: 'Success' }), null);
});

test('observed users with only non-module events still appear with zero usage', () => {
  const rows = modules.aggregateEvents([
    ev('Login', {}, { company_id: 'c1', distinct_id: 'u1', email: 'login-only@example.com' }),
    ev('Dashboard Viewed', {}, { company_id: 'c1', distinct_id: 'u1', email: 'login-only@example.com' }),
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u2', email: 'active@example.com' }),
  ]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].users.length, 2, 'login-only user is a member, not just mapped users');
  const idle = rows[0].users.find(user => user.id === 'u1');
  assert(idle, 'idle user is nested beneath the company');
  assert.deepEqual(idle.totals, { ap: 0, ar: 0, transactions: 0, gst: 0, sync: 0 });
  assert.equal(idle.email, 'login-only@example.com');
  assert.equal(rows[0].totals.ap, 1, 'company total still reconciles');
});

test('company name fallback prefers directory, then event name, then id', () => {
  assert.equal(modules.resolveCompanyName('Acme Pvt Ltd', 'Older Name', 'id-1'), 'Acme Pvt Ltd');
  assert.equal(modules.resolveCompanyName('', 'Raigad Carbides', 'id-2'), 'Raigad Carbides');
  assert.equal(modules.resolveCompanyName(null, 'ABC', 'id-3'), 'id-3', 'placeholder event names are skipped');
  assert.equal(modules.resolveCompanyName(null, null, 'id-4'), 'id-4', 'raw id is the last resort');
  assert.equal(modules.usableCompanyName('  Laundry Labs  '), 'Laundry Labs');
  assert.equal(modules.usableCompanyName('dummy'), null);
  const sql = read('supabase/companies-live.sql');
  assert(sql.includes('read_company_users'), 'membership RPC exists');
  assert(sql.includes('read_company_names'), 'name-fallback RPC exists');
  assert(sql.includes("'delete company'"), 'placeholder denylist is documented in SQL');
});

test('2. company totals reconcile to nested users plus unattributed activity', () => {
  const rows = modules.aggregateEvents([
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u1', email: 'a@example.com' }),
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u1', email: 'a@example.com' }),
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u2', email: 'b@example.com' }),
    ev('Transaction Status', { itemsCount: 2 }, { company_id: 'c1', distinct_id: '', email: '' }),
    ev('Login', {}, { company_id: 'c1', distinct_id: 'u1' }),
  ]);
  assert.equal(rows.length, 1);
  const [company] = rows;
  assert.equal(company.totals.ap, 3);
  assert.equal(company.totals.transactions, 1);
  const users = company.users.reduce((sum, user) => sum + user.totals.ap, 0);
  const unattributed = company.users.find(user => user.id === modules.UNATTRIBUTED_ID);
  assert(unattributed, 'unattributed activity is preserved explicitly');
  assert.equal(unattributed.email, modules.UNATTRIBUTED_LABEL);
  assert.equal(company.totals.ap, users + 0); // unattributed holds transactions here
  const txnUsers = company.users.reduce((sum, user) => sum + user.totals.transactions, 0);
  assert.equal(company.totals.transactions, txnUsers);
});

test('3. same company names remain separate by company ID', () => {
  const rows = modules.aggregateEvents([
    ev('Upload', { type: 'bill' }, { company_id: 'id-a', distinct_id: 'u1' }),
    ev('Upload', { type: 'bill' }, { company_id: 'id-b', distinct_id: 'u9' }),
  ]);
  assert.equal(rows.length, 2);
  assert.notEqual(rows[0].id, rows[1].id);
});

test('4. multiple users under one company keep their own totals', () => {
  const rows = modules.aggregateEvents([
    ev('Upload', { type: 'bill' }, { company_id: 'c1', distinct_id: 'u1', email: 'one@example.com' }),
    ev('Upload', { type: 'invoice' }, { company_id: 'c1', distinct_id: 'u2', email: 'two@example.com' }),
    ev('Upload', { type: 'invoice' }, { company_id: 'c1', distinct_id: 'u2', email: 'two@example.com' }),
  ]);
  assert.equal(rows[0].users.length, 2);
  assert.equal(rows[0].totals.ap, 1);
  assert.equal(rows[0].totals.ar, 2);
});

test('5. zero-usage company behavior is a real zero, unavailable is flagged', () => {
  const rows = modules.aggregateEvents([]);
  assert.equal(rows.length, 0);
  const source = read('components/companies/companies-dashboard.tsx');
  assert(source.includes('No events in this module'), 'real zero is labeled, not hidden');
  assert(source.includes('unavailable, not zero'), 'unavailable ranges are dashed, never zeroed');
});

test('6. search by company matches the parent row', () => {
  const rows = [
    { id: 'a', name: 'Northstar Traders', users: [], totals: modules.emptyTotals() },
    { id: 'b', name: 'Harbor Supplies', users: [], totals: modules.emptyTotals() },
  ];
  assert(modules.matchesSearch(rows[0], 'northstar'));
  assert(!modules.matchesSearch(rows[1], 'northstar'));
});

test('7. search by user email keeps the parent and its totals', () => {
  const row = {
    id: 'a', name: 'Northstar Traders',
    users: [{ email: 'a@example.com' }, { email: 'b@example.com' }],
    totals: { ap: 20, ar: 0, transactions: 0, gst: 0, sync: 0 },
  };
  assert(modules.matchesSearch(row, 'B@EXAMPLE.com'));
  assert.equal(row.users.length, 2, 'other users are not dropped');
  assert.equal(row.totals.ap, 20, 'parent total is not recalculated');
});

test('8. sorting works for every module and the name column', () => {
  const rows = [
    { id: 'c', name: 'C Co', users: [], totals: { ap: 1, ar: 5, transactions: 0, gst: 2, sync: 0 } },
    { id: 'a', name: 'A Co', users: [], totals: { ap: 3, ar: 1, transactions: 9, gst: 0, sync: 4 } },
    { id: 'b', name: 'B Co', users: [], totals: { ap: 3, ar: 2, transactions: 1, gst: 7, sync: 1 } },
  ];
  for (const key of ['name', 'ap', 'ar', 'transactions', 'gst', 'sync']) {
    const sorted = modules.sortRows(rows, key, key === 'name' ? 'asc' : 'desc');
    assert.equal(sorted.length, 3, `sort ${key}`);
  }
  const byAp = modules.sortRows(rows, 'ap', 'desc');
  assert.deepEqual(byAp.map(row => row.id), ['a', 'b', 'c'], 'ap desc with stable id tie-break');
  const byName = modules.sortRows(rows, 'name', 'asc');
  assert.deepEqual(byName.map(row => row.id), ['a', 'b', 'c']);
  assert.equal(JSON.stringify(rows.map(row => row.id)), JSON.stringify(['c', 'a', 'b']), 'input is not mutated');
});

test('9. date filtering uses Asia/Kolkata calendar boundaries', () => {
  // 2026-09-30 23:30 UTC is 2026-10-01 05:00 IST: October, not September.
  assert(!modules.inRangeIST('2026-09-30T23:30:00+00:00', '2026-09-01', '2026-09-30'));
  assert(modules.inRangeIST('2026-09-30T23:30:00+00:00', '2026-10-01', '2026-10-31'));
  assert(modules.inRangeIST('2026-09-10T10:00:00+00:00', '2026-09-01', '2026-09-30'));
  assert(modules.inRangeIST('2026-09-10T10:00:00+00:00', null, null));
});

test('10. module modal scoping at company level uses a null user', () => {
  const source = read('components/companies/companies-dashboard.tsx');
  assert(source.includes('user_id: target.user?.id ?? null'), 'company scope sends null user');
  assert(source.includes('Company total'), 'company scope is labeled');
});

test('11. module modal scoping at user level and unattributed sentinel', () => {
  const source = read('components/companies/companies-dashboard.tsx');
  assert(source.includes('moduleButton(company, user,'), 'user cells open user scope');
  assert(source.includes('User scope'), 'user scope is labeled');
  const edge = read('supabase/functions/companies-dashboard/index.ts');
  assert(edge.includes('"__unattributed__"'), 'edge maps the unattributed sentinel');
  assert(edge.includes('UNATTRIBUTED_LABEL'), 'edge labels unattributed activity');
});

test('15. failed backend request never falls back to fixtures', () => {
  const route = read('app/api/companies/route.ts');
  assert(!route.includes('fixture'), 'route has no fixture import or fallback');
  assert(route.includes('companies_data_unavailable'), 'missing OIDC fails closed');
  assert(route.includes('status: 503'), 'backend failure is a 503, not zeros');
  const component = read('components/companies/companies-dashboard.tsx');
  assert(component.includes('No fixture values are shown'), ' UI states the honest error');
  assert(!component.includes('customerFixtures') && !component.includes('lib/customer'), 'component has no fixture wiring');
  assert(!fs.existsSync(path.join(root, 'lib/customer/fixtures.ts')), 'fixture adapter is gone');
});

test('16. pagination slices rows without changing totals', () => {
  const totals = { ap: 5, ar: 1, transactions: 0, gst: 0, sync: 2 };
  const page = [{ id: 'a', totals }].slice(0, 10);
  assert.equal(page[0].totals.ap, 5);
  const source = read('components/companies/companies-dashboard.tsx');
  assert(source.includes('PAGE_SIZE'), 'page size is centralized');
});

test('17. /customer remains the route and /companies is not created', () => {
  assert(fs.existsSync(path.join(root, 'app/customer/page.tsx')), '/customer page exists');
  assert(!fs.existsSync(path.join(root, 'app/companies')), 'no /companies route exists');
  const page = read('app/customer/page.tsx');
  assert(!page.includes('redirect'), 'customer does not redirect away');
  assert(page.includes('CompaniesDashboard'), 'customer renders the Companies page');
});

test('18. visible navigation label is Companies', () => {
  const nav = read('lib/prototype/customer-navigation.ts');
  assert(nav.includes('<strong>Companies</strong>'), 'prototype menu labels Companies');
  assert(nav.includes('href="/customer"'), 'prototype menu links to /customer');
  const dashboard = read('components/companies/companies-dashboard.tsx');
  assert(dashboard.includes('<h1>Companies</h1>'), 'page title is Companies');
  assert(dashboard.includes('<span>Companies</span>'), 'dashboard switcher says Companies');
  assert(!dashboard.includes('>Customer<'), 'no visible Customer wording remains');
});

test('no raw Supabase or secret keys in the browser bundle', () => {
  for (const relative of ['components/companies/companies-dashboard.tsx', 'lib/companies/types.ts', 'lib/companies/modules.ts']) {
    const source = read(relative);
    assert(!source.includes('service_role'), `${relative} has no service_role`);
    assert(!source.includes('SUPABASE_'), `${relative} reads no Supabase env`);
    assert(!source.includes('supabase.co'), `${relative} calls no Supabase URL`);
  }
  const route = read('app/api/companies/route.ts');
  assert(!route.includes('NEXT_PUBLIC'), 'no public env leaks at the boundary');
});

test('all shipped TypeScript and JSX transpile without syntax errors', () => {
  for (const relative of [
    'components/companies/companies-dashboard.tsx', 'app/customer/page.tsx',
    'app/api/companies/route.ts', 'lib/companies/types.ts', 'lib/companies/modules.ts',
    'lib/prototype/customer-navigation.ts',
  ]) {
    const result = ts.transpileModule(read(relative), {
      fileName: relative, reportDiagnostics: true,
      compilerOptions: { jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.ESNext },
    });
    assert.equal(result.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0, relative);
  }
});
