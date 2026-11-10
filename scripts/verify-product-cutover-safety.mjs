// Static, offline safety checks for the staged Product production switch.
// No credentials, DB connection, or cutover actions are used by this test.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = path => readFileSync(new URL("../"+path,import.meta.url),"utf8");
const writer=read("supabase/cutover/PRODUCT_writer_job7_manual_switch.sql");
const readers=read("supabase/cutover/PRODUCT_readers_manual_switch.sql");
const crons=read("supabase/cutover/PRODUCT_refresh_crons_manual_switch.sql");
const legacyReaderRestore=read("supabase/rollback/20261107_product_readers_part_02.sql");
const preview=read("supabase/migrations/20261110211000_product_overview_source_preview_rpc.sql");

const names=[...readers.matchAll(/CREATE OR REPLACE FUNCTION public\."(read_[^"]+)"\(/g)].map(m=>m[1]);
assert.equal(names.length,105,"Exactly 105 public Product reader wrappers are required");
assert.equal(new Set(names).size,names.length,"Reader wrappers must be unique");
assert.match(readers,/FUNCTION public\."read_companies_usage"\([\s\S]*?SET statement_timeout TO '20s'[\s\S]*?\$product_proxy\$;/,
  "The Companies usage reader must retain its live 20-second timeout");
assert.match(legacyReaderRestore,
 /FUNCTION public\.read_companies_usage\([\s\S]*?SET statement_timeout TO '20s'[\s\S]*?\$function\$;/,
 "Reader rollback must also retain the 20-second Companies timeout");
for(const [name,sql] of [["writer",writer],["readers",readers]]){
 assert.match(sql,/canonical Overview page manifest is stale, missing, unsealed or mixed-generation/,
  name+" cutover must require a live sealed five-member private Overview manifest");
 assert.match(sql,/product_snapshot_current/,
  name+" cutover must remain tied to published snapshot generation");
 assert.match(sql,/aia_product_cutover\.approved/,
  name+" cutover requires explicit operator approval");
}
assert.match(writer,/sync_incremental_function_url/,
 "Original legacy writer Vault path must remain explicit");
assert.match(writer,/product_shadow_canonical_function_url_v1/,
 "Canonical writer must use isolated shadow Vault URL");
assert.match(crons,/cron\.alter_job\(47, active := false\)/);
assert.match(crons,/cron\.alter_job\(48, active := false\)/);
assert.match(crons,/aia_product_cutover\.canonical_writer_active/,
 "Refresh cron switch cannot run before new canonical writer");
assert.match(preview,/SECURITY DEFINER/);
assert.match(preview,/REVOKE ALL ON FUNCTION public\.shadow_product_overview_source_preview_v1\(\)/);
assert.match(preview,/FROM PUBLIC,anon,authenticated/);
assert.match(read("app/api/product-overview-source-canary/route.ts"),/VERCEL_ENV !== "preview"/,
 "Source preview must be disabled in production");
console.log("Product cutover static safety: 105 readers, timeout, fresh Overview, cron 47/48, Vault and preview restrictions passed.");
