/* Run: node --test tests/customer-usage.test.cjs. Uses the existing TypeScript dev dependency. */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const root = path.resolve(__dirname, '..');
const cache = new Map();
function load(relative) {
  const file = path.resolve(root, relative);
  if (cache.has(file)) return cache.get(file);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  const module = { exports: {} };
  new Function('require', 'module', 'exports', output.outputText)(name => name.startsWith('.') ? load(path.relative(root, path.resolve(path.dirname(file), name + '.ts'))) : require(name), module, module.exports);
  cache.set(file, module.exports);
  return module.exports;
}
const usage = load('lib/customer/usage.ts');
const { customerFixtures } = load('lib/customer/fixtures.ts');
const { withCustomerNavigation } = load('lib/prototype/customer-navigation.ts');
const customers = customerFixtures();
const custom = (start, end = start) => ({ preset: 'custom', start, end });
const sum = (rows, key) => rows.reduce((a, row) => a + (row.totals[key] || 0), 0);

// Execute ONLY the original fixture builder, never the UI or network code.
function originalFixtures() {
  const script = fs.readFileSync(path.join(root, 'public/prototype/runtime-v2-2.js'), 'utf8');
  const first = script.indexOf(' const names='), last = script.indexOf(' const activityCache=');
  assert(first >= 0 && last > first, 'original fixture boundaries exist');
  const ctx = { SNAPSHOT_DATE: usage.SNAPSHOT_DATE };
  vm.runInNewContext(`
    const addDays=(iso,days)=>new Date(Date.parse(iso+'T12:00:00Z')+days*86400000).toISOString().slice(0,10);
    const hashText=value=>{let h=2166136261;for(const char of value){h^=char.charCodeAt(0);h=Math.imul(h,16777619);}return h>>>0;};
    ${script.slice(first, last)}
    result=users;
  `, ctx);
  return JSON.parse(JSON.stringify(ctx.result));
}
const original = originalFixtures();

test('fixture has identical company IDs and user attribution to Product Overview', () => {
  const expected = original.flatMap(u => u.companies.map(c => ({ id: c.id, name: c.name, email: u.email })));
  assert.deepEqual(customers.map(c => ({ id: c.id, name: c.name, email: c.users[0].email })), expected);
  assert.equal(new Set(customers.map(c => c.id)).size, customers.length);
});
test('every event count, date, and flow matches the original fixture', () => {
  const expected = original.flatMap(u => u.companies.map(c => c.events.map(({ date, flow, count }) => ({ date, flow, count }))));
  const normalize = events => [...events].sort((a, b) => a.date.localeCompare(b.date) || a.flow.localeCompare(b.flow) || a.count - b.count);
  assert.deepEqual(customers.map(c => normalize(c.users[0].events)), expected.map(normalize));
});
for (const range of [usage.LIFETIME, ...['2026-07','2026-08','2026-09','2026-10'].map(m => custom(m)), custom('2026-07','2026-09')]) {
  test(`per-customer and nested-user totals reconcile for ${JSON.stringify(range)}`, () => {
    const { start, end } = usage.windowFor(range);
    const rows = usage.aggregateCustomers(customers, range);
    const source = new Map(original.flatMap(u => u.companies.map(c => [c.id, c.events])));
    for (const row of rows) {
      const events = source.get(row.id).filter(e => e.date >= start && e.date <= end);
      for (const [key, flows] of [['ap',['bills']],['ar',['invoices']],['transactions',['statements','transactions']],['sync',['sync']]]) {
        assert.equal(row.totals[key], events.filter(e => flows.includes(e.flow)).reduce((n,e)=>n+e.count,0));
        assert.equal(row.totals[key], row.users.reduce((n,u)=>n+u.totals[key],0));
      }
      assert.equal(row.totals.gst, null);
    }
  });
}
test('multiple users sum to one customer, not to display-name groups', () => {
  const event = count => [{date:'2026-09-10',flow:'bills',count}];
  const fixture = [{id:'a',name:'Same name',integration:'Tally',users:[{id:'u1',email:'a@example.com',events:event(8)},{id:'u2',email:'b@example.com',events:event(12)}]},{id:'b',name:'Same name',integration:'Tally',users:[]}];
  const rows=usage.aggregateCustomers(fixture,usage.LIFETIME);
  assert.equal(rows.length,2);assert.equal(rows[0].totals.ap,20);assert.equal(rows[1].totals.ap,0);
  const filtered=usage.filterAndSort(rows,{...usage.EMPTY_FILTERS,query:'b@example.com'},'name','asc');
  assert.equal(filtered.length,1);assert.equal(filtered[0].users.length,2);assert.equal(filtered[0].totals.ap,20);
});
test('unavailable historical data is null rather than zero', () => {
  for(const row of usage.aggregateCustomers(customers,custom('2026-05'))) for(const {key} of usage.MODULES) assert.equal(row.totals[key],null);
});
test('current month is capped to the original snapshot', () => {
  assert.equal(usage.windowFor(custom('2026-10')).end,'2026-10-04');
  assert.equal(usage.windowFor(custom('2026-09')).end,'2026-09-30');
});
test('completed-month presets preserve the existing calendar convention', () => {
  assert.deepEqual(usage.presetRange('3'),{preset:'3',start:'2026-07',end:'2026-09'});
  assert.equal(usage.presetRange('12').start,'2025-10');
  assert.equal(usage.shiftMonth('2026-01',-1),'2025-12');
});
test('inverted or incomplete ranges are rejected',()=>{
  assert.throws(()=>usage.windowFor(custom('2026-09','2026-08')));
  assert.throws(()=>usage.windowFor({preset:'custom',start:null,end:null}));
});
test('activity filters partition the available customer population',()=>{
  const rows=usage.aggregateCustomers(customers,custom('2026-10'));
  const active=usage.filterAndSort(rows,{...usage.EMPTY_FILTERS,usage:'active'},'name','asc');
  const inactive=usage.filterAndSort(rows,{...usage.EMPTY_FILTERS,usage:'inactive'},'name','asc');
  assert.equal(active.length+inactive.length,rows.length);assert(active.length>0);assert(inactive.length>0);
});
test('unknown historical activity is not classified as inactive',()=>{
  const rows=usage.aggregateCustomers(customers,custom('2026-05'));
  assert.equal(usage.filterAndSort(rows,{...usage.EMPTY_FILTERS,usage:'inactive'},'name','asc').length,0);
});
test('integration and user search work together without changing totals',()=>{
  const rows=usage.aggregateCustomers(customers,usage.LIFETIME), candidate=rows.find(r=>r.integration==='Zoho Books');
  const filtered=usage.filterAndSort(rows,{...usage.EMPTY_FILTERS,query:candidate.users[0].email.toUpperCase(),integration:'Zoho Books'},'name','asc');
  assert(filtered.some(r=>r.id===candidate.id));assert.deepEqual(filtered.find(r=>r.id===candidate.id).totals,candidate.totals);
});
test('sorting is numeric, stable, and does not mutate input',()=>{
  const rows=usage.aggregateCustomers(customers,usage.LIFETIME),before=JSON.stringify(rows);
  const sorted=usage.filterAndSort(rows,usage.EMPTY_FILTERS,'transactions','desc');
  for(let i=1;i<sorted.length;i++)assert(sorted[i-1].totals.transactions>=sorted[i].totals.transactions);
  assert.equal(JSON.stringify(rows),before);
});
test('pagination includes boundaries and adjacent pages',()=>{
  assert.deepEqual(usage.pageNumbers(1,1),[1]);assert.deepEqual(usage.pageNumbers(5,12),[1,4,5,6,12]);
});
test('customer navigation is additive and leaves existing markup unchanged',()=>{
  const input='<div><button id="retention-menu-item">Retention</button></div>';
  const out=withCustomerNavigation(input);assert(out.includes('href="/customer"'));assert(out.includes(input.slice(0,-6)));assert(out.endsWith('</div>'));
  assert.throws(()=>withCustomerNavigation('<main/>'));
});
test('new Customer page does not import the prototype or inject HTML',()=>{
  const source=fs.readFileSync(path.join(root,'components/customer/customer-dashboard.tsx'),'utf8');
  assert(!source.includes('dangerouslySetInnerHTML'));assert(!source.includes('innerHTML'));assert(!source.includes('runtime-v2'));
  assert(source.includes('po-user-table'));assert(source.includes('po-company-subtable'));
});
test('all source TypeScript and JSX transpile without syntax errors',()=>{
  for (const relative of ['components/customer/customer-dashboard.tsx','components/prototype-surface.tsx','app/customer/page.tsx','lib/customer/usage.ts','lib/customer/fixtures.ts','lib/prototype/customer-navigation.ts']) {
    const result=ts.transpileModule(fs.readFileSync(path.join(root,relative),'utf8'),{fileName:relative,reportDiagnostics:true,compilerOptions:{jsx:ts.JsxEmit.ReactJSX,target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.ESNext}});
    assert.equal(result.diagnostics.filter(d=>d.category===ts.DiagnosticCategory.Error).length,0,relative);
  }
});
