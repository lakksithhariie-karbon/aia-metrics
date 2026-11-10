// Build-time check: no silent nulling of severity during Jira repair.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
for (const file of [
  "supabase/functions/jira-sync-engineering/index.ts",
]) {
  const source = readFileSync(new URL("../" + file, import.meta.url), "utf8");
  assert.match(source,
    /return \[\{ issue_id: issue\.id, severity_value: sourceValue \}\];/,
    "Jira severity repair payload must match jsonb_to_recordset column");
  assert.match(source,
    /as x\(issue_id bigint, severity_value jsonb\)/,
    "Jira SQL repair mapping changed unexpectedly");
  assert.doesNotMatch(source,
    /return \[\{ issue_id: issue\.id, value: sourceValue \}\];/,
    "Do not restore the broken key that silently stores NULL");
}
const sql = readFileSync(new URL("../supabase/migrations/20261110234500_engineering_sprint_upsert_dedup_v1.sql",import.meta.url),"utf8");
assert.match(sql,/distinct on \(\(sp->>'id'\)::bigint\)/);
assert.match(sql,/when 'closed' then 3/);
assert.match(sql,/on conflict \(id\) do update/);
console.log("Jira source fixes verified: severity JSON mapping + deterministic sprint upsert.");
