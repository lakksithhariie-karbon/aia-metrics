// jira-sync: incremental Jira Cloud -> Supabase sync (supabase/functions/jira-sync).
// DB writes go through the migration SQL functions (derive_issue, derive_issue_children,
// load_field_history, refresh_reference_tables) so derivation logic stays version-controlled
// there and this file only orchestrates paging + upserts, per the ops handbook split.
import postgres from "postgres";

const SEARCH_PAGE_SIZE = 100;
const SPRINT_PAGE_SIZE = 100;
const RAW_UPSERT_BATCH = 250;
const DERIVE_CHUNK = 500;
const CHANGELOG_BATCH = 1000;
const MAX_ATTEMPTS = 5;
const REQUEST_TIMEOUT_MS = 120_000;
const COMMENT_PAGE_SIZE = 100;
const SEARCH_COMMENT_CAP = 20; // search/jql truncates comments at 20; deep-fetch above this
const WATERMARK_LOOKBACK_MS = 5 * 60_000;
const MAX_SEARCH_PAGES = 2000;
const MAX_COMMENT_PAGES = 200;
const MAX_CHANGELOG_PAGES = 200;
const DEFAULT_PROJECT_KEY = "SPEND";

type Json = any;

interface JiraIssue {
  id: number;
  key: string;
  fields: Json;
}

interface JiraSprintMember {
  id: number;
  fields: Json;
}

interface SyncError {
  scope: string;
  message: string;
  payload?: Json;
}

interface SyncResult {
  projectKey: string;
  synced: number;
  searched: number;
  watermark: string | null;
  commentsDeepFetched: number;
  sprintsTouched: number;
  sprintsReconciled: number;
  sprintMembersReconciled: number;
  staleSprintMembershipsRemoved: number;
  severityFieldsSeen: number;
  severityCorrectionsApplied: number;
  historyRows: number;
  errors: SyncError[];
}

interface Ctx {
  base: string;
  projectKey: string;
  authHeaders: Record<string, string>;
  errors: SyncError[];
}

type Stage =
  | "source"
  | "watermark"
  | "search"
  | "raw upsert"
  | "derive"
  | "comments"
  | "changelog"
  | "sprint membership"
  | "reference refresh";

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(v: Json, status = 200): Response {
  return new Response(JSON.stringify(v), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders() },
  });
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function truncate(s: string, n: number): string {
  return s.length <= n ? s : `${s.slice(0, n)}...`;
}

// JQL accepts "yyyy-MM-dd HH:mm" (no timezone notation) and Jira parses it in
// the SITE's timezone (karbonworks: IST, UTC+5:30). We therefore shift the UTC
// instant by the IST offset before formatting, so "updated >= T" matches the
// instant we mean. The 5-minute lookback absorbs second-level skew only.
function jqlDatetime(d: Date): string {
  const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
  const ist = new Date(d.getTime() + IST_OFFSET_MS);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${ist.getUTCFullYear()}-${p(ist.getUTCMonth() + 1)}-${p(ist.getUTCDate())} ${p(
    ist.getUTCHours(),
  )}:${p(ist.getUTCMinutes())}`;
}

function configuredProjectKey(): string {
  const projectKey = (Deno.env.get("JIRA_PROJECT_KEY") ?? DEFAULT_PROJECT_KEY).trim();
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(projectKey)) {
    throw new Error("JIRA_PROJECT_KEY must be a Jira project key such as SPEND");
  }
  return projectKey;
}

async function fetchWithRetry(url: string, init: RequestInit, ctx: Ctx, scope: string): Promise<Json> {
  let lastErr: unknown = null;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const res = await fetch(url, { ...init, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
      if (res.status === 429) {
        lastErr = new Error(`${scope}: HTTP 429 rate-limited`);
        if (attempt === MAX_ATTEMPTS) break;
        const retryAfter = Number(res.headers.get("retry-after") ?? "5");
        await sleep((Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : 5) * 1000);
        continue;
      }
      if (res.status >= 500 && attempt < MAX_ATTEMPTS) {
        lastErr = new Error(`${scope}: HTTP ${res.status}`);
        await sleep(2 ** attempt * 1000);
        continue;
      }
      if (!res.ok) {
        throw new Error(`${scope}: HTTP ${res.status} — ${truncate(await res.text(), 400)}`);
      }
      return await res.json();
    } catch (e) {
      // The scope is prefixed to HTTP errors (for example, "auth: HTTP
      // 401"). Do not retry hard authentication or project-access failures.
      if (e instanceof Error && /: HTTP [45]\d\d(?:\s|$)/.test(e.message)) throw e;
      lastErr = e;
      if (attempt < MAX_ATTEMPTS) {
        await sleep(2 ** attempt * 1000);
        continue;
      }
      break;
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(`${scope}: request failed`);
}

// ---------------------------------------------------------------- sync stages

async function getWatermark(sql: postgres.Sql): Promise<Date> {
  const rows: { watermark: unknown }[] = await sql`
    select coalesce(max(updated_at), now() - interval '2 days') as watermark from issues`;
  const wm = rows[0]?.watermark;
  const d = wm instanceof Date ? wm : new Date(String(wm));
  if (Number.isNaN(d.getTime())) throw new Error(`watermark unparsable: ${wm}`);
  return d;
}

async function validateJiraSource(ctx: Ctx): Promise<void> {
  // A Jira search can legally return an empty result when the account cannot
  // browse a project. Validate both authentication and project visibility so
  // that this condition cannot be recorded as a green no-change sync.
  await fetchWithRetry(
    `${ctx.base}/rest/api/3/myself`,
    { method: "GET", headers: ctx.authHeaders },
    ctx,
    "auth",
  );
  const project = await fetchWithRetry(
    `${ctx.base}/rest/api/3/project/${encodeURIComponent(ctx.projectKey)}`,
    { method: "GET", headers: ctx.authHeaders },
    ctx,
    `project ${ctx.projectKey}`,
  );
  if (String(project?.key ?? "").toUpperCase() !== ctx.projectKey.toUpperCase()) {
    throw new Error(`project ${ctx.projectKey}: Jira returned an unexpected project`);
  }
}

async function searchAllIssues(ctx: Ctx, watermark: Date): Promise<JiraIssue[]> {
  const since = new Date(watermark.getTime() - WATERMARK_LOOKBACK_MS);
  const jql = `project = ${ctx.projectKey} AND updated >= "${jqlDatetime(since)}"`;
  const issues: JiraIssue[] = [];
  let nextPageToken: string | undefined;
  for (let page = 0; page < MAX_SEARCH_PAGES; page++) {
    const body: Json = { jql, fields: ["*all"], maxResults: SEARCH_PAGE_SIZE };
    if (nextPageToken) body.nextPageToken = nextPageToken;
    const resp: Json = await fetchWithRetry(
      `${ctx.base}/rest/api/3/search/jql`,
      { method: "POST", headers: { ...ctx.authHeaders, "content-type": "application/json" }, body: JSON.stringify(body) },
      ctx,
      "search",
    );
    // Jira normally returns an array here. Treat a malformed optional field as
    // an empty page so one bad response cannot crash the whole sync run. The
    // response status and pagination markers are still handled normally.
    const returnedIssues = Array.isArray(resp.issues) ? resp.issues : [];
    for (const it of returnedIssues) {
      if (!it || typeof it !== "object") continue;
      issues.push({ id: Number(it.id), key: String(it.key), fields: it.fields ?? {} });
    }
    if (resp.isLast || !resp.nextPageToken) break;
    nextPageToken = resp.nextPageToken;
  }
  return issues;
}

/**
 * Jira's Sprint custom field can retain historical sprint IDs. The Agile
 * sprint-issues endpoint is the source of truth for current membership, so use
 * it to reconcile the dashboard window after each issue derivation. This is
 * deliberately per sprint: an issue may legitimately appear in multiple
 * sprints (including the intentional Sprint 46/48 overlap).
 */
async function searchSprintIssues(ctx: Ctx, sprintId: number): Promise<JiraSprintMember[]> {
  const issues = new Map<number, JiraSprintMember>();
  let nextPageToken: string | undefined;
  let startAt = 0;

  for (let page = 0; page < MAX_SEARCH_PAGES; page++) {
    const params = new URLSearchParams({
      maxResults: String(SPRINT_PAGE_SIZE),
      fields: "key,customfield_10794",
    });
    if (nextPageToken) params.set("nextPageToken", nextPageToken);
    else params.set("startAt", String(startAt));

    const resp: Json = await fetchWithRetry(
      `${ctx.base}/rest/agile/1.0/sprint/${sprintId}/issue?${params.toString()}`,
      { method: "GET", headers: ctx.authHeaders },
      ctx,
      `sprint ${sprintId}`,
    );
    if (!Array.isArray(resp.issues)) {
      throw new Error(`sprint ${sprintId}: Jira returned a malformed issues page`);
    }

    for (const issue of resp.issues) {
      const id = Number(issue?.id);
      if (!Number.isSafeInteger(id) || id <= 0) {
        throw new Error(`sprint ${sprintId}: Jira returned an issue without a valid ID`);
      }
      issues.set(id, { id, fields: issue.fields ?? {} });
    }

    if (resp.isLast === true) return [...issues.values()];
    if (typeof resp.nextPageToken === "string" && resp.nextPageToken.length > 0) {
      nextPageToken = resp.nextPageToken;
      continue;
    }

    // Some Jira Cloud tenants still return the older startAt/total shape for
    // this endpoint even though the enhanced API documents token pagination.
    // Accept that only when the server supplies a valid total and a non-empty
    // page (or an explicitly empty result); otherwise fail closed.
    const total = Number(resp.total);
    if (Number.isSafeInteger(total) && total >= 0) {
      if (issues.size >= total) return [...issues.values()];
      const pageCount = resp.issues.length;
      if (pageCount === 0) {
        throw new Error(`sprint ${sprintId}: Jira returned an incomplete empty page`);
      }
      startAt = Number.isSafeInteger(Number(resp.startAt))
        ? Number(resp.startAt) + pageCount
        : startAt + pageCount;
      continue;
    }

    throw new Error(`sprint ${sprintId}: Jira pagination returned no completion marker`);
  }

  throw new Error(`sprint ${sprintId}: Jira exceeded ${MAX_SEARCH_PAGES} pages`);
}

function normalizeSeverity(value: Json): string | null {
  let v = Array.isArray(value) ? value[0] : value;
  if (v && typeof v === "object") {
    if (typeof v.value === "string") v = v.value;
    else if (typeof v.name === "string") v = v.name;
  }
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

async function reconcileDashboardSprintMembership(
  sql: postgres.Sql,
  ctx: Ctx,
): Promise<{
  sprints: number;
  jiraMembers: number;
  removedMemberships: number;
  severityFieldsSeen: number;
  severityCorrections: number;
}> {
  const window: { id: number }[] = await sql`
    select id from v_dashboard_sprints order by start_date desc, id desc`;
  let jiraMembers = 0;
  let removedMemberships = 0;
  let severityFieldsSeen = 0;
  let severityCorrectionsApplied = 0;

  for (const { id: sprintId } of window) {
    const sourceIssues = await searchSprintIssues(ctx, sprintId);
    const issueIds = sourceIssues.map((issue) => issue.id);
    const existing: { issue_id: number; severity: string | null }[] = issueIds.length === 0
      ? []
      : await sql`
          select issue_id, severity from issues
          where issue_id = any(${issueIds}::bigint[])
            and project_key = ${ctx.projectKey}`;
    if (existing.length !== issueIds.length) {
      const present = new Set(existing.map((row) => Number(row.issue_id)));
      const missing = issueIds.filter((issueId) => !present.has(issueId));
      throw new Error(
        `sprint ${sprintId}: Jira returned ${missing.length} members absent from the local issue table; refusing to reconcile`,
      );
    }

    // The severity audit found a stale source-field value. Jira's sprint
    // endpoint includes this field, allowing narrowly scoped repair without
    // replacing the rest of a raw issue payload (notably its full comments).
    const severityById = new Map(existing.map((row) => [Number(row.issue_id), row.severity]));
    const severityCorrections = sourceIssues.flatMap((issue) => {
      if (!Object.hasOwn(issue.fields, "customfield_10794")) return [];
      severityFieldsSeen++;
      const sourceValue = issue.fields.customfield_10794 ?? null;
      if (normalizeSeverity(sourceValue) === severityById.get(issue.id)) return [];
      return [{ issue_id: issue.id, value: sourceValue }];
    });
    if (severityCorrections.length > 0) {
      await sql`
        update raw_issues r
           set payload = jsonb_set(
                 r.payload,
                 '{fields,customfield_10794}',
                 coalesce(x.severity_value, 'null'::jsonb),
                 true
               ),
               jql_synced_at = now()
          from jsonb_to_recordset(${sql.json(severityCorrections)}::jsonb)
               as x(issue_id bigint, severity_value jsonb)
         where r.issue_id = x.issue_id
           and r.deleted_at is null`;
      await sql`select * from derive_issue(${severityCorrections.map((x) => x.issue_id)}::bigint[])`;
      severityCorrectionsApplied += severityCorrections.length;
    }

    const [result] = await sql`
      select * from reconcile_dashboard_sprint_membership(
        ${sprintId}::bigint,
        ${issueIds}::bigint[]
      )`;
    jiraMembers += issueIds.length;
    removedMemberships += Number(result?.removed_count ?? 0);
  }

  return {
    sprints: window.length,
    jiraMembers,
    removedMemberships,
    severityFieldsSeen,
    severityCorrections: severityCorrectionsApplied,
  };
}

async function upsertRawIssues(sql: postgres.Sql, ctx: Ctx, issues: JiraIssue[]): Promise<number> {
  let synced = 0;
  for (const batch of chunk(issues, RAW_UPSERT_BATCH)) {
    try {
      await sql`
        insert into raw_issues (issue_id, issue_key, payload, jql_synced_at, deleted_at)
        select (x->>'id')::bigint, x->>'key', x, now(), null
        from jsonb_array_elements(${sql.json(batch)}::jsonb) as x
        on conflict (issue_id) do update
          set payload = excluded.payload,
              issue_key = excluded.issue_key,
              jql_synced_at = now(),
              deleted_at = null`;
      synced += batch.length;
    } catch (e) {
      ctx.errors.push({
        scope: "issue",
        message: e instanceof Error ? e.message : String(e),
        payload: { ids: batch.map((i) => i.id) },
      });
    }
  }
  return synced;
}

async function deriveAll(sql: postgres.Sql, ctx: Ctx, ids: number[], sprints: Set<string>): Promise<void> {
  for (const c of chunk(ids, DERIVE_CHUNK)) {
    try {
      await sql`select * from derive_issue(${c}::bigint[])`;
      await sql`select * from derive_issue_children(${c}::bigint[])`;
      for (const r of await sql`
        select distinct sp->>'id' as sprint_id
        from raw_issues r
        cross join lateral jsonb_array_elements(
          case
            when jsonb_typeof(r.payload#>'{fields,customfield_10020}') = 'array'
              then r.payload#>'{fields,customfield_10020}'
            else '[]'::jsonb
          end
        ) sp
        where r.issue_id = any(${c}::bigint[])
          and sp->>'id' is not null`) {
        sprints.add(r.sprint_id);
      }
    } catch (e) {
      ctx.errors.push({ scope: "issue", message: e instanceof Error ? e.message : String(e), payload: { ids: c } });
    }
  }
}

async function deepFetchComments(sql: postgres.Sql, ctx: Ctx, seen: JiraIssue[]): Promise<{ deepIds: number[]; fetched: number }> {
  const deepIds: number[] = [];
  for (const iss of seen) {
    const comment = iss.fields?.comment;
    const total = comment?.total;
    if (typeof total !== "number" || total <= SEARCH_COMMENT_CAP) continue;
    try {
      const all: Json[] = [];
      let startAt = 0;
      for (let page = 0; page < MAX_COMMENT_PAGES; page++) {
        const resp: Json = await fetchWithRetry(
          `${ctx.base}/rest/api/3/issue/${encodeURIComponent(iss.key)}/comment?maxResults=${COMMENT_PAGE_SIZE}&startAt=${startAt}`,
          { method: "GET", headers: ctx.authHeaders },
          ctx,
          "comments",
        );
        const cs = Array.isArray(resp.comments) ? resp.comments : [];
        all.push(...cs);
        if (all.length >= (resp.total ?? all.length) || cs.length === 0 || resp.isLast) break;
        startAt += typeof resp.maxResults === "number" && resp.maxResults > 0 ? resp.maxResults : cs.length;
      }
      const merged = { comments: all, startAt: 0, maxResults: COMMENT_PAGE_SIZE, total: all.length };
      const upd: { issue_id: number }[] = await sql`
        update raw_issues
        set payload = jsonb_set(payload, '{fields,comment}', ${sql.json(merged)}::jsonb)
        where issue_id = ${iss.id}
        returning issue_id`;
      if (upd.length > 0) {
        deepIds.push(iss.id);
      }
    } catch (e) {
      ctx.errors.push({ scope: "comments", message: e instanceof Error ? e.message : String(e), payload: { issue_id: iss.id, issue_key: iss.key } });
    }
  }
  return { deepIds, fetched: deepIds.length };
}

async function loadChangelog(sql: postgres.Sql, ctx: Ctx, ids: number[]): Promise<number> {
  let historyRows = 0;
  for (const c of chunk(ids, CHANGELOG_BATCH)) {
    try {
      const acc: Record<string, Json> = {};
      let nextPageToken: string | undefined;
      for (let page = 0; page < MAX_CHANGELOG_PAGES; page++) {
        const body: Json = {
          issueIdsOrKeys: c.map(String),
          maxResults: CHANGELOG_BATCH,
        };
        if (nextPageToken) body.nextPageToken = nextPageToken;
        const resp: Json = await fetchWithRetry(
          `${ctx.base}/rest/api/3/changelog/bulkfetch`,
          { method: "POST", headers: { ...ctx.authHeaders, "content-type": "application/json" }, body: JSON.stringify(body) },
          ctx,
          "changelog",
        );
        const issueChangeLogs = Array.isArray(resp.issueChangeLogs) ? resp.issueChangeLogs : [];
        for (const icl of issueChangeLogs) {
          if (!icl || typeof icl !== "object") continue;
          const k = String(icl.issueId);
          const histories = Array.isArray(icl.changeHistories) ? icl.changeHistories : [];
          acc[k] = {
            changeHistories: [...(acc[k]?.changeHistories ?? []), ...histories],
          };
        }
        if (!resp.nextPageToken) break;
        nextPageToken = resp.nextPageToken;
      }
      if (Object.keys(acc).length === 0) continue;
      const [before] = await sql`select count(*)::int as c from issue_field_history where issue_id = any(${c}::bigint[])`;
      await sql`select * from load_field_history(${sql.json(acc)}::jsonb)`;
      const [after] = await sql`select count(*)::int as c from issue_field_history where issue_id = any(${c}::bigint[])`;
      historyRows += Math.max(0, (after?.c ?? 0) - (before?.c ?? 0));
    } catch (e) {
      ctx.errors.push({ scope: "changelog", message: e instanceof Error ? e.message : String(e), payload: { ids: c } });
    }
  }
  return historyRows;
}

async function writeSyncErrors(sql: postgres.Sql, syncId: number, errors: SyncError[]): Promise<void> {
  // Insert one error at a time.  The previous JSON-array expansion could
  // mask the original failure with "cannot extract elements from a scalar"
  // when the driver encoded an error payload as a scalar.
  for (const error of errors) {
    await sql`
      insert into sync_errors (sync_id, scope, message, payload)
      values (
        ${syncId}::bigint,
        ${error.scope},
        ${truncate(error.message, 2000)},
        ${sql.json(error.payload ?? null)}::jsonb
      )`;
  }
}

// ---------------------------------------------------------------- entry point

async function runSync(sql: postgres.Sql, setStage: (stage: Stage) => void): Promise<SyncResult> {
  const projectKey = configuredProjectKey();
  const ctx: Ctx = {
    base: (Deno.env.get("JIRA_URL") ?? "").replace(/\/+$/, ""),
    projectKey,
    authHeaders: {
      authorization: `Basic ${btoa(`${Deno.env.get("JIRA_EMAIL")}:${Deno.env.get("JIRA_TOKEN")}`)}`,
      accept: "application/json",
    },
    errors: [],
  };
  const result: SyncResult = {
    projectKey,
    synced: 0,
    searched: 0,
    watermark: null,
    commentsDeepFetched: 0,
    sprintsTouched: 0,
    sprintsReconciled: 0,
    sprintMembersReconciled: 0,
    staleSprintMembershipsRemoved: 0,
    severityFieldsSeen: 0,
    severityCorrectionsApplied: 0,
    historyRows: 0,
    errors: ctx.errors,
  };

  setStage("source");
  await validateJiraSource(ctx);
  setStage("watermark");
  const watermark = await getWatermark(sql);
  result.watermark = watermark.toISOString();
  setStage("search");
  const seen = await searchAllIssues(ctx, watermark);
  result.searched = seen.length;

  // dedupe by issue id; a repeated id in one statement would error on conflict
  const byId = new Map<number, JiraIssue>();
  for (const iss of seen) byId.set(iss.id, iss);
  const issues = [...byId.values()];
  const ids = issues.map((i) => i.id);

  setStage("raw upsert");
  result.synced += await upsertRawIssues(sql, ctx, issues);
  const sprints = new Set<string>();
  setStage("derive");
  await deriveAll(sql, ctx, ids, sprints);

  setStage("comments");
  const { deepIds, fetched } = await deepFetchComments(sql, ctx, issues);
  result.commentsDeepFetched = fetched;
  await deriveAll(sql, ctx, deepIds, sprints);
  result.sprintsTouched = sprints.size;

  setStage("changelog");
  result.historyRows += await loadChangelog(sql, ctx, ids);

  setStage("sprint membership");
  const sprintMembership = await reconcileDashboardSprintMembership(sql, ctx);
  result.sprintsReconciled = sprintMembership.sprints;
  result.sprintMembersReconciled = sprintMembership.jiraMembers;
  result.staleSprintMembershipsRemoved = sprintMembership.removedMemberships;
  result.severityFieldsSeen = sprintMembership.severityFieldsSeen;
  result.severityCorrectionsApplied = sprintMembership.severityCorrections;

  setStage("reference refresh");
  try {
    await sql`select * from refresh_reference_tables()`;
  } catch (e) {
    ctx.errors.push({ scope: "reference", message: e instanceof Error ? e.message : String(e) });
  }
  // Dashboard materialized views are refreshed by the database cron job after
  // this ingestion job.  Keeping the expensive refresh out of the Edge
  // request prevents a 2-minute statement timeout from turning a successful
  // Jira ingest into a failed sync.
  return result;
}

/**
 * This endpoint is invoked by pg_cron using a service-role JWT from Vault.
 * Supabase's Edge gateway must first verify the signature/expiry
 * (verify_jwt=true at deploy time). Decode only to enforce the role:
 * an otherwise valid user JWT is NOT allowed to run a privileged Jira sync.
 *
 * Do not compare to SUPABASE_SERVICE_ROLE_KEY: a project's built-in key may
 * differ from the legacy, still-valid Vault service-role JWT.
 * Never log or echo the token or its claims.
 */
function authorizeCronRequest(req: Request): Response | null {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }
  const header = req.headers.get("authorization") ?? "";
  if (!header.startsWith("Bearer ")) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  try {
    const jwt = header.slice(7).trim();
    const parts = jwt.split(".");
    if (parts.length !== 3 || !parts[1] || !parts[2]) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = payload + "=".repeat((4 - (payload.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));
    if (claims?.role !== "service_role") {
      return json({ ok: false, error: "unauthorized" }, 401);
    }
  } catch {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  return null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const authorizationError = authorizeCronRequest(req);
  if (authorizationError) return authorizationError;
  const started = Date.now();

  // APP_DB_URL (not SUPABASE_DB_URL) — the Supabase secrets store rejects
  // the reserved SUPABASE_ prefix, renamed accordingly.
  const required = ["JIRA_URL", "JIRA_EMAIL", "JIRA_TOKEN", "APP_DB_URL"];
  const missing = required.filter((k) => !Deno.env.get(k));
  if (missing.length > 0) {
    return json({ ok: false, error: `missing secrets: ${missing.join(", ")}`, synced: 0, comments_deep_fetched: 0, duration_ms: Date.now() - started }, 500);
  }

  const sql = postgres(Deno.env.get("APP_DB_URL")!, {
    ssl: "require",
    prepare: false, // safe under Supabase pgbouncer transaction pooling
    connection: { search_path: "jira,public" }, // migration: unqualified SQL resolves in jira, then public
    max: 5,
    idle_timeout: 20,
  });

  let syncId: number | null = null;
  let stage: Stage = "watermark";
  try {
    const log: { id: number }[] = await sql`
      insert into sync_log (started_at, trigger, kind) values (now(), 'cron', 'incremental')
      returning id`;
    syncId = log[0].id;

    const r = await runSync(sql, (nextStage) => {
      stage = nextStage;
    });

    const durationMs = Date.now() - started;
    await writeSyncErrors(sql, syncId, r.errors);
    await sql`
      update sync_log set
        finished_at = now(),
        duration_ms = ${durationMs},
        issues_upserted = ${r.synced},
        sprints_upserted = ${r.sprintsTouched},
        history_rows = ${r.historyRows},
        errors_count = ${r.errors.length}
      where id = ${syncId}`;

    return json(
      {
        ok: r.errors.length === 0,
        project_key: r.projectKey,
        searched: r.searched,
        synced: r.synced,
        watermark: r.watermark,
        comments_deep_fetched: r.commentsDeepFetched,
        sprints_reconciled: r.sprintsReconciled,
        sprint_members_reconciled: r.sprintMembersReconciled,
        stale_sprint_memberships_removed: r.staleSprintMembershipsRemoved,
        severity_fields_seen: r.severityFieldsSeen,
        severity_corrections_applied: r.severityCorrectionsApplied,
        duration_ms: durationMs,
      },
      r.errors.length === 0 ? 200 : 500,
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    const durationMs = Date.now() - started;
    try {
      if (syncId !== null) {
        await writeSyncErrors(sql, syncId, [{ scope: stage, message }]);
        await sql`
          update sync_log set finished_at = now(), duration_ms = ${durationMs}, errors_count = errors_count + 1
          where id = ${syncId}`;
      } else {
        await sql`
          insert into sync_log (started_at, finished_at, trigger, kind, errors_count, duration_ms)
          values (now() - (${durationMs} * interval '1 ms'), now(), 'cron', 'incremental', 1, ${durationMs})`;
      }
    } catch {
      // logging itself unavailable; nothing further to do
    }
    return json({ ok: false, error: message, project_key: Deno.env.get("JIRA_PROJECT_KEY") ?? DEFAULT_PROJECT_KEY, searched: 0, synced: 0, watermark: null, comments_deep_fetched: 0, duration_ms: durationMs }, 500);
  } finally {
    await sql.end({ timeout: 5 });
  }
});
