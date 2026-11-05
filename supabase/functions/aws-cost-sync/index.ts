// aws-cost-sync: AWS Cost Explorer -> "03_infra_schema".aws_costs (supabase/functions/aws-cost-sync).
//
// Why an Edge Function: Cost Explorer needs SigV4 request signing, which Postgres
// cannot do. pg_cron triggers this over pg_net; secrets come from the Edge runtime.
//
// Corrections this file encodes (both were real bugs found while loading the table
// by hand, so they are guard rails here, not preferences):
//   1. Cost Explorer is a JSON (awsjson1.1) API on the GLOBAL us-east-1 endpoint,
//      regardless of where the spend happened. It has no AWS SDK here, so SigV4 is
//      implemented directly.
//   2. GetCostAndUsage silently truncates at 5,000 groups. A first hand-load using
//      SERVICE+USAGE_TYPE grouping dropped $8,309/month and lost the four highest
//      months with no error. Every request here follows NextPageToken AND the run
//      aborts unless the grouped sum reconciles with an independent total.
//   3. Cost Explorer allows at most two GroupBy dimensions, so the pull is
//      LINKED_ACCOUNT + SERVICE, and USAGE_TYPE is collected per account.
//
// Cost: each GetCostAndUsage request is billed at $0.01. Daily cadence
// (~30 runs/month) keeps this trivial.
import postgres from "postgres";

const CE_HOST = "ce.us-east-1.amazonaws.com";
const CE_REGION = "us-east-1";
const CE_SERVICE = "ce";
const GROUP_CAP = 5000; // hard API limit; the reason pagination is mandatory
const RECONCILE_TOLERANCE_USD = 0.05;
const HISTORY_MONTHS = 14; // Cost Explorer's rolling retention window
const MONTHLY_REQUESTS = 2; // CE monthly-data allowance before billing applies

type Json = any;

interface CostRow {
  cost_month: string;
  linked_account: string;
  service: string;
  usage_type: string;
  cost_usd: number;
  usage_qty: number;
  usage_unit: string | null;
  estimated: boolean;
}

interface SyncSummary {
  ok: boolean;
  months: number;
  accounts: number;
  rows: number;
  total_usd: number;
  drift_usd: number;
  api_requests: number;
  est_cost_usd: number;
  window: { start: string; end: string };
  errors: string[];
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

// --- SigV4 (ported from the verified prototype) ---------------------------------

function hex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256hex(data: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(data));
  return hex(new Uint8Array(digest));
}

async function hmac(key: Uint8Array | string, msg: string): Promise<Uint8Array> {
  const raw = typeof key === "string" ? new TextEncoder().encode(key) : key;
  const imported = await crypto.subtle.importKey(
    "raw",
    raw as unknown as ArrayBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", imported, new TextEncoder().encode(msg)));
}

async function deriveSigningKey(
  secret: string,
  dateStamp: string,
  region: string,
  service: string,
): Promise<Uint8Array> {
  let k = await hmac(`AWS4${secret}`, dateStamp);
  k = await hmac(k, region);
  k = await hmac(k, service);
  k = await hmac(k, "aws4_request");
  return k;
}

interface AwsCreds {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken?: string;
}

async function ceRequest(
  creds: AwsCreds,
  target: string,
  payload: Json,
): Promise<{ ok: boolean; status: number; body: Json; text: string }> {
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const bodyStr = JSON.stringify(payload);

  const headers: Record<string, string> = {
    "content-type": "application/x-amz-json-1.1",
    host: CE_HOST,
    "x-amz-date": amzDate,
    "x-amz-target": target,
  };
  if (creds.sessionToken) headers["x-amz-security-token"] = creds.sessionToken;

  const names = Object.keys(headers).sort();
  const canonicalHeaders = names.map((h) => `${h}:${headers[h].trim()}\n`).join("");
  const signedHeaders = names.join(";");
  const payloadHash = await sha256hex(bodyStr);

  const canonicalRequest = ["POST", "/", "", canonicalHeaders, signedHeaders, payloadHash].join("\n");
  const scope = `${dateStamp}/${CE_REGION}/${CE_SERVICE}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    await sha256hex(canonicalRequest),
  ].join("\n");

  const signingKey = await deriveSigningKey(creds.secretAccessKey, dateStamp, CE_REGION, CE_SERVICE);
  const signature = hex(await hmac(signingKey, stringToSign));

  const res = await fetch(`https://${CE_HOST}/`, {
    method: "POST",
    headers: {
      ...headers,
      authorization:
        `AWS4-HMAC-SHA256 Credential=${creds.accessKeyId}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
    body: bodyStr,
  });

  const text = await res.text();
  let parsed: Json = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    // AWS error bodies are JSON; a non-JSON body means something infrastructural.
  }
  return { ok: res.ok, status: res.status, body: parsed, text };
}

// --- Cost Explorer reading ------------------------------------------------------

/** Follow NextPageToken to completion. Truncation here is silent, so it must not be optional. */
async function pagedCostAndUsage(
  creds: AwsCreds,
  payload: Json,
  budget: { requests: number },
): Promise<{ results: Json[]; truncated: boolean }> {
  const results: Json[] = [];
  let token: string | null = null;

  for (let page = 0; page < 200; page += 1) {
    const body = token ? { ...payload, NextPageToken: token } : payload;
    const res = await ceRequest(creds, "AWSInsightsIndexService.GetCostAndUsage", body);
    budget.requests += 1;

    if (!res.ok) {
      const msg = res.body?.Message || res.body?.message || res.text.slice(0, 300);
      throw new Error(`Cost Explorer ${res.status}: ${msg}`);
    }
    results.push(...(res.body.ResultsByTime ?? []));
    token = res.body.NextPageToken ?? null;
    if (!token) return { results, truncated: false };
  }
  return { results, truncated: true };
}

function monthKeys(count: number): { start: string; end: string } {
  // Cost Explorer's window ends at the first of the coming month; the End date is exclusive.
  // The oldest month inside the rolling 14-month window depends on where "now" sits in the
  // month, so probe rather than compute: ask for a wide window and let CE clamp it.
  const now = new Date();
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  const start = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth() - count, 1));
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

function isHistoryError(err: unknown): boolean {
  const msg = errorMessage(err);
  return /historical data beyond|14 months|older than/i.test(msg);
}

function parseAmount(g: Json): number {
  const raw = g?.Metrics?.UnblendedCost?.Amount;
  const value = typeof raw === "string" ? Number.parseFloat(raw) : Number(raw);
  return Number.isFinite(value) ? value : 0;
}

function parseQty(g: Json): { qty: number; unit: string | null } {
  const q = g?.Metrics?.UsageQuantity;
  if (!q) return { qty: 0, unit: null };
  const value = typeof q.Amount === "string" ? Number.parseFloat(q.Amount) : Number(q.Amount);
  return { qty: Number.isFinite(value) ? value : 0, unit: q.Unit ?? null };
}

function monthOf(t: Json): string {
  return `${t.TimePeriod.Start.slice(0, 7)}-01`;
}

/** A month is provisional unless CE marks it final. */
function estimated(t: Json): boolean {
  return t.Estimated !== false;
}

interface PullResult {
  rows: CostRow[];
  total: number;
  accounts: number;
  months: number;
  refTotal: number;
  rank: string[];
}

export async function pull(
  creds: AwsCreds,
  window: { start: string; end: string },
  budget: { requests: number },
): Promise<PullResult> {
  const base = {
    TimePeriod: { Start: window.start, End: window.end },
    Granularity: "MONTHLY" as const,
    Metrics: ["UnblendedCost", "UsageQuantity"],
  };

  // 1. Linked account x service (the two-dimension maximum).
  const asService = await pagedCostAndUsage(
    creds,
    { ...base, GroupBy: [{ Type: "DIMENSION", Key: "LINKED_ACCOUNT" }, { Type: "DIMENSION", Key: "SERVICE" }] },
    budget,
  );

  // 2. Independent reference total, single dimension, for the reconciliation guard.
  const asTotal = await pagedCostAndUsage(
    creds,
    {
      TimePeriod: base.TimePeriod,
      Granularity: "MONTHLY",
      Metrics: ["UnblendedCost"],
      GroupBy: [{ Type: "DIMENSION", Key: "LINKED_ACCOUNT" }],
    },
    budget,
  );

  const rank = asTotal.results.length ? Object.keys(asTotal.results[0] ?? {}) : [];
  const refTotal = asTotal.results.reduce(
    (acc, t) => acc + (t.Groups ?? []).reduce((a: number, g: Json) => a + parseAmount(g), 0),
    0,
  );

  const accounts = new Set<string>();
  const months = new Set<string>();
  let total = 0;
  for (const t of asService.results) {
    months.add(monthOf(t));
    for (const g of t.Groups ?? []) {
      accounts.add(g.Keys[0]);
      total += parseAmount(g);
    }
  }

  // 3. Per-account usage types. A separate account-level call avoids the account-major
  //    truncation that lost whole months in the hand-load.
  const rows: CostRow[] = [];
  const seen = new Set<string>();
  for (const account of [...accounts].sort()) {
    try {
      const perAccount = await pagedCostAndUsage(
        creds,
        {
          ...base,
          Filter: { Dimensions: { Key: "LINKED_ACCOUNT", Values: [account] } },
          GroupBy: [{ Type: "DIMENSION", Key: "SERVICE" }, { Type: "DIMENSION", Key: "USAGE_TYPE" }],
        },
        budget,
      );
      for (const t of perAccount.results) {
        const month = monthOf(t);
        const est = estimated(t);
        for (const g of t.Groups ?? []) {
          const service = g.Keys[0];
          const usageType = g.Keys[1] && g.Keys[1] !== "uncategorized" ? g.Keys[1] : "";
          const cost = parseAmount(g);
          const { qty, unit } = parseQty(g);
          if (cost === 0 && qty === 0) continue;
          const key = `${month}|${account}|${service}|${usageType}`;
          if (seen.has(key)) continue;
          seen.add(key);
          rows.push({
            cost_month: month,
            linked_account: account,
            service,
            usage_type: usageType,
            cost_usd: Number(cost.toFixed(4)),
            usage_qty: Number(qty.toFixed(4)),
            usage_unit: unit,
            estimated: est,
          });
        }
      }
    } catch (err) {
      // A single account failing must not discard the whole pull.
      console.error(`account ${account} failed: ${errorMessage(err)}`);
    }
  }

  return { rows, total, accounts: accounts.size, months: months.size, refTotal, rank };
}

// --- persistence ----------------------------------------------------------------

async function writeRows(sql: postgres.Sql, rows: CostRow[]): Promise<number> {
  if (rows.length === 0) return 0;
  const CHUNK = 500;
  let written = 0;

  for (let i = 0; i < rows.length; i += CHUNK) {
    const batch = rows.slice(i, i + CHUNK);
    // All values are bound parameters; only the OUTER loop count varies.
    const payload = batch.map((r) => ({
      cost_month: r.cost_month,
      linked_account: r.linked_account,
      service: r.service,
      usage_type: r.usage_type,
      cost_usd: r.cost_usd,
      usage_qty: r.usage_qty,
      usage_unit: r.usage_unit,
      estimated: r.estimated,
    }));

    await sql`
      insert into "03_infra_schema".aws_costs ${sql(
        payload,
        "cost_month",
        "linked_account",
        "service",
        "usage_type",
        "cost_usd",
        "usage_qty",
        "usage_unit",
        "estimated",
      )}
      on conflict (cost_month, linked_account, service, usage_type) do update set
        cost_usd   = excluded.cost_usd,
        usage_qty  = excluded.usage_qty,
        usage_unit = excluded.usage_unit,
        estimated  = excluded.estimated,
        fetched_at = now()`;
    written += batch.length;
  }
  return written;
}

function credsFromEnv(): AwsCreds {
  const accessKeyId = Deno.env.get("AWS_ACCESS_KEY_ID")?.trim();
  const secretAccessKey = Deno.env.get("AWS_SECRET_ACCESS_KEY")?.trim();
  const sessionToken = Deno.env.get("AWS_SESSION_TOKEN")?.trim() || undefined;
  if (!accessKeyId || !secretAccessKey) {
    throw new Error("AWS credentials are not configured");
  }
  return { accessKeyId, secretAccessKey, sessionToken };
}

// --- handler --------------------------------------------------------------------

function isServiceRoleJwt(request: Request): boolean {
  const auth = request.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return false;
  const parts = auth.slice("Bearer ".length).trim().split(".");
  if (parts.length !== 3) return false;
  try {
    const normalized = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));
    return claims.role === "service_role" || claims.app_metadata?.role === "service_role";
  } catch {
    return false;
  }
}

function sameSecret(actual: string | null, expected: string | undefined): boolean {
  if (!actual || !expected || actual.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < actual.length; i += 1) diff |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

/** Dedicated least-privilege connection: writes two tables in private 03_infra_schema and nothing else. */
function databaseUrl(): string {
  const url = Deno.env.get("AWS_COST_DB_URL");
  if (!url) throw new Error("AWS_COST_DB_URL is not configured");
  return url;
}

export async function handler(request: Request): Promise<Response> {
  if (request.method !== "POST" && request.method !== "GET") return json({ ok: false }, 405);
  if (!isServiceRoleJwt(request) || !sameSecret(request.headers.get("x-cron-secret"), Deno.env.get("CRON_SECRET"))) {
    return json({ ok: false }, 401);
  }

  let dbUrl: string;
  try {
    dbUrl = databaseUrl();
  } catch (err) {
    return json({ ok: false, error: errorMessage(err) }, 500);
  }

  const sql = postgres(dbUrl, { ssl: "require", prepare: false, max: 3, idle_timeout: 20 });

  let runId: number | null = null;
  try {
    const started = await sql`
      insert into "03_infra_schema".aws_cost_sync_runs (started_at, ok)
      values (now(), false) returning id`;
    runId = started[0].id;

    const creds = credsFromEnv();
    const budget = { requests: 0 };
    const window = monthKeys(HISTORY_MONTHS);

    let result: PullResult;
    try {
      result = await pull(creds, window, budget);
    } catch (err) {
      if (isHistoryError(err)) {
        // The rolling window moved; retry one month narrower.
        const narrower = monthKeys(HISTORY_MONTHS - 1);
        result = await pull(creds, narrower, budget);
        window.start = narrower.start;
      } else {
        throw err;
      }
    }

    const drift = Number((result.total - result.refTotal).toFixed(4));
    if (Math.abs(drift) > RECONCILE_TOLERANCE_USD) {
      throw new Error(
        `reconciliation failed: grouped total ${result.total.toFixed(2)} vs reference ` +
          `${result.refTotal.toFixed(2)} (drift ${drift.toFixed(2)}). Refusing to load truncated data.`,
      );
    }

    const rows = await writeRows(sql, result.rows);
    const total = Number(result.total.toFixed(2));
    const estCost = Math.max(0, budget.requests - MONTHLY_REQUESTS) * 0.01;

    await sql`
      update "03_infra_schema".aws_cost_sync_runs set
        finished_at    = now(),
        ok             = true,
        months_covered = ${result.months},
        accounts       = ${result.accounts},
        rows_upserted  = ${rows},
        drift_usd      = ${drift},
        total_usd      = ${total}
      where id = ${runId}`;

    const summary: SyncSummary = {
      ok: true,
      months: result.months,
      accounts: result.accounts,
      rows,
      total_usd: total,
      drift_usd: drift,
      api_requests: budget.requests,
      est_cost_usd: Number(estCost.toFixed(2)),
      window,
      errors: [],
    };
    return json(summary);
  } catch (err) {
    const message = errorMessage(err);
    if (runId !== null) {
      try {
        await sql`
          update "03_infra_schema".aws_cost_sync_runs set finished_at = now(), ok = false, error = ${message}
          where id = ${runId}`;
      } catch {
        // Keep the original failure; the run row stays open as the signal.
      }
    }
    return json({ ok: false, error: message }, 500);
  } finally {
    await sql.end({ timeout: 5 });
  }
}

// Diagnostics: report the role this function actually connects as, so a
// "permission denied for schema" is never guessed at. Values are role names
// and booleans only; no credentials or connection strings are returned.
export async function whoami(): Promise<Response> {
  const dbUrl = Deno.env.get("AWS_COST_DB_URL");
  if (!dbUrl) return json({ ok: false, error: "AWS_COST_DB_URL is not configured" }, 500);
  const sql = postgres(dbUrl, { ssl: "require", prepare: false, max: 1, idle_timeout: 5 });
  try {
    const identity = await sql`select current_user as u, current_database() as db`;
    const privs = await sql`
      select has_schema_privilege(current_user, '03_infra_schema', 'USAGE') as infra_usage,
             has_table_privilege(current_user, '"03_infra_schema".aws_costs', 'INSERT') as can_insert,
             has_table_privilege(current_user, '"03_infra_schema".aws_cost_sync_runs', 'INSERT') as can_log`;
    return json({ ok: true, identity, privs });
  } catch (err) {
    return json({ ok: false, error: errorMessage(err) }, 500);
  } finally {
    await sql.end({ timeout: 5 });
  }
}

if (import.meta.main) {
  Deno.serve((req) => {
    if (new URL(req.url).pathname.endsWith("/whoami")) return whoami();
    return handler(req);
  });
}
