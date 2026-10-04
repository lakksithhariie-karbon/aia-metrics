#!/usr/bin/env node
/* Conformance check: replays testdata/companies-module-vectors.json against the
 * DEPLOYED Supabase bridge and asserts the SQL mapping matches the TypeScript
 * twin (lib/companies/modules.ts). Manual step in the reconciliation check.
 *
 * Requires env (never committed): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 * The service_role key is server-side only; this script runs on this machine,
 * never in the browser. Usage: node scripts/verify-companies-bridge.mjs
 */
const fs = require('node:fs');
const path = require('node:path');

const BASE = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!BASE || !KEY) {
  console.error('missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in env');
  process.exit(2);
}
const vectors = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'testdata', 'companies-module-vectors.json'), 'utf8'));

async function rpc(fn, params) {
  const response = await fetch(`${BASE}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  if (!response.ok) throw new Error(`${fn} ${response.status}: ${(await response.text()).slice(0, 300)}`);
  return response.json();
}

(async () => {
  let failures = 0;
  for (const vector of vectors) {
    const props = vector.properties ?? {};
    const [module, subtype, items] = await Promise.all([
      rpc('company_module_for', { p_event_name: vector.event_name, p_properties: props }),
      rpc('company_subtype_for', { p_event_name: vector.event_name, p_properties: props }),
      rpc('company_items_for', { p_event_name: vector.event_name, p_properties: props }),
    ]);
    const itemValue = Array.isArray(items) ? items[0]?.company_items_for ?? items : items;
    const problems = [];
    if (module !== vector.module) problems.push(`module sql=${module} expected=${vector.module}`);
    if (subtype !== vector.subtype) problems.push(`subtype sql=${subtype} expected=${vector.subtype}`);
    const sqlItems = itemValue == null ? null : Number(itemValue);
    if (sqlItems !== vector.items) problems.push(`items sql=${sqlItems} expected=${vector.items}`);
    if (problems.length) {
      failures += 1;
      console.error(`MISMATCH ${vector.event_name} ${JSON.stringify(props)} :: ${problems.join('; ')}`);
    }
  }
  // Usable-name fallback checks (SQL twin of usableCompanyName).
  const names = [['ABC', null], ['dummy', null], ['  Laundry Labs  ', 'Laundry Labs'], ['', null]];
  for (const [raw, expected] of names) {
    const got = await rpc('company_usable_name', { p_raw: raw });
    if (got !== expected) { failures += 1; console.error(`NAME MISMATCH ${JSON.stringify(raw)} sql=${got} expected=${expected}`); }
  }
  // Anon must NOT be able to call the bridge (defense in depth).
  for (const [fn, params] of [
    ['read_companies_usage', { p_from: null, p_to: null }],
    ['read_company_users', {}],
    ['read_company_names', { p_company_id: null }],
  ]) {
    const anonProbe = await fetch(`${BASE}/rest/v1/rpc/${fn}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(params),
    });
    console.log(`anon ${fn} status: ${anonProbe.status} (want 401/403/404)`);
    if (anonProbe.ok) { failures += 1; console.error(`ANON CAN READ ${fn}`); }
  }
  console.log(failures === 0 ? `OK: ${vectors.length} vectors match SQL` : `${failures} FAILURES`);
  process.exit(failures === 0 ? 0 : 1);
})().catch(error => { console.error(error); process.exit(1); });
