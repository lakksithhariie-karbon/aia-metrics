import { NextResponse } from "next/server";

// Migration-only. SSO-protected Vercel preview on the Product shadow branch.
// Reads one verified private source generation through a service-role-only RPC.
// It NEVER stages/publishes snapshots, changes routing, or returns identities.
export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const maxDuration = 60;

type RecordValue = Record<string, unknown>;
const isRecord = (v: unknown): v is RecordValue =>
  v !== null && typeof v === "object" && !Array.isArray(v);
const headers = { "Cache-Control": "private, no-store" };
const respond = (data: RecordValue, status: number) =>
  NextResponse.json(data, { status, headers });

export async function GET() {
  if (
    process.env.VERCEL_ENV !== "preview" ||
    process.env.VERCEL_GIT_COMMIT_REF !== "product/numbered-schema-shadow-20261106"
  ) return respond({ error: "not_found" }, 404);

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return respond({ passed: false, reason: "private_credentials_unconfigured" }, 503);

  try {
    const r = await fetch(url + "/rest/v1/rpc/shadow_product_overview_source_preview_v1", {
      method: "POST",
      cache: "no-store",
      signal: AbortSignal.timeout(52_000),
      headers: {
        apikey: key,
        Authorization: "Bearer " + key,
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
      body: "{}",
    });
    if (r.status !== 200) return respond({ passed: false, upstream_status: r.status }, 502);

    const data: unknown = await r.json();
    if (!isRecord(data)) return respond({ passed: false, reason: "invalid_response" }, 502);
    const keys = ["activity", "charts", "workflow", "friction", "adoption"] as const;
    const contracts: Record<string, string> = {
      activity: "overview_activity_source_v1",
      charts: "overview_active_charts_source_v1",
      workflow: "overview_workflow_source_v1",
      friction: "overview_friction_source_v1",
      adoption: "overview_adoption_source_v1",
    };
    const source = data.source_watermark_at;
    const validComponents = keys.every(
      k => isRecord(data[k]) &&
        data[k].contract === contracts[k] &&
        data[k].source_watermark_at === source,
    );
    const charts = isRecord(data.charts) ? data.charts : null;
    const weekly = charts && isRecord(charts.weekly) ? charts.weekly.rows : null;
    const workflow = isRecord(data.workflow) ? data.workflow : null;
    const friction = isRecord(data.friction) ? data.friction : null;
    const passed = data.contract === "shadow_overview_source_preview_v1" &&
      data.source_schema === "01_product_schema" &&
      data.snapshot_published === false &&
      typeof source === "string" && !Number.isNaN(Date.parse(source)) &&
      typeof data.as_of === "string" &&
      typeof data.event_count === "number" && data.event_count > 0 &&
      Date.now() - Date.parse(source) < 86_400_000 &&
      validComponents &&
      Array.isArray(weekly) && weekly.length === 12 &&
      Array.isArray(workflow?.weekly) && workflow.weekly.length === 12 &&
      Array.isArray(friction?.rows) && friction.rows.length === 5;

    const activity = isRecord(data.activity) ? data.activity : {};
    return respond({
      passed,
      source_schema: data.source_schema,
      source_watermark_at: source,
      event_count: data.event_count,
      components_verified: validComponents ? keys.length : 0,
      as_of: data.as_of,
      dau: activity.dau,
      wau: activity.wau_current,
      mau: activity.mau_current,
      snapshot_published: false,
    }, passed ? 200 : 502);
  } catch {
    return respond({ passed: false, reason: "source_request_failed" }, 502);
  }
}
