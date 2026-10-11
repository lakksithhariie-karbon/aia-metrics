import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const fn = read("supabase/functions/jira-sync/index.ts");
const sql = read("supabase/migrations/20261010_jira_reference_project_rename_fix.sql");
const help = read("supabase/functions/jira-sync/README.md");

assert.match(fn,/function authorizeCronRequest\(req: Request\)/);
assert.match(fn,/req\.method !== "POST"/);
assert.match(fn,/claims\?\.role !== "service_role"/);
assert.match(fn,/jwt\.split\("\."\)/);
assert.doesNotMatch(fn,/Deno\.env\.get\("SUPABASE_SERVICE_ROLE_KEY"\)/,
  "Built-in and Vault service-role JWTs can be different: rely on verified claims");
assert.ok(fn.indexOf("authorizeCronRequest(req)") < fn.indexOf("const sql = postgres("),
  "Fail-closed authorization must precede DB and Jira access.");
assert.match(sql,/distinct on \(r\.payload#>>'\{fields,project,key\}'\)/);
assert.match(sql,/r\.jql_synced_at desc,/);
assert.match(sql,/r\.deleted_at is null/);
assert.match(help,/verify_jwt=true/);
assert.doesNotMatch(fn, /JIRA_TOKEN\s*=\s*["']/,
  "Do not hardcode a Jira secret");
console.log("GitHub Jira foundation verified: authenticated POST, deterministic reference upsert, no committed token.");
