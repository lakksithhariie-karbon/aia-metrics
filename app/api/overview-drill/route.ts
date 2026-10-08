import { NextResponse } from "next/server";
import {
  readOverviewCoreCompany,
  readOverviewCoreUsers,
  type OverviewCoreModule,
  type OverviewDrillSegment,
} from "../../../lib/overview/drill";

export const dynamic = "force-dynamic";

const privateHeaders = { "Cache-Control": "private, no-store" };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function reply(body: Record<string, unknown> | object, status = 200) {
  return NextResponse.json(body, { status, headers: privateHeaders });
}

export async function POST(request: Request) {
  // Same-origin access only. Supabase RPCs cannot be invoked by anon keys.
  const origin = request.headers.get("origin");
  const host = request.headers.get("host");
  if (origin && (!host || new URL(origin).host !== host)) {
    return reply({ error: "forbidden_origin" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    const payload: unknown = await request.json();
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return reply({ error: "invalid_body" }, 400);
    }
    body = payload as Record<string, unknown>;
  } catch {
    return reply({ error: "invalid_json" }, 400);
  }
  const snapshotId = body.snapshot_id;
  if (typeof snapshotId !== "number" || !Number.isSafeInteger(snapshotId) || snapshotId < 1) {
    return reply({ error: "invalid_snapshot" }, 400);
  }

  const timeout = new AbortController();
  const timer = setTimeout(() => timeout.abort(), 24_000);
  try {
    if (body.action === "users") {
      if (!["wau", "mau", "mau_only"].includes(String(body.segment))) {
        return reply({ error: "invalid_segment" }, 400);
      }
      const segment = body.segment as OverviewDrillSegment;
      const module: OverviewCoreModule =
        body.module === "ap" || body.module === "ar" ||
        body.module === "transactions" ? body.module : "all";
      const query = typeof body.query === "string" ? body.query.trim().slice(0, 80) : "";
      const page = typeof body.page === "number" && Number.isFinite(body.page)
        ? Math.max(1, Math.min(10000, Math.floor(body.page))) : 1;
      const pageSize = typeof body.page_size === "number" && Number.isFinite(body.page_size)
        ? Math.max(1, Math.min(25, Math.floor(body.page_size))) : 10;

      const result = await readOverviewCoreUsers({
        snapshotId, segment, module, query, page, pageSize, signal: timeout.signal,
      });
      if (!result) return reply({ error: "snapshot_expired", message: "Refresh the dashboard for the latest data." }, 409);
      return reply(result);
    }

    if (body.action === "company") {
      const scope = body.scope;
      const userId = body.user_id;
      const companyId = body.company_id;
      if ((scope !== "wau" && scope !== "mau") ||
          typeof userId !== "string" || !uuid.test(userId) ||
          typeof companyId !== "string" || !uuid.test(companyId)) {
        return reply({ error: "invalid_company_parameters" }, 400);
      }
      const result = await readOverviewCoreCompany({
        snapshotId, scope, userId, companyId, signal: timeout.signal,
      });
      if (!result) return reply({ error: "detail_unavailable_or_snapshot_expired" }, 404);
      return reply(result);
    }
    return reply({ error: "invalid_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    console.error("overview-core-drill", message.slice(0, 140));
    return reply({ error: "overview_drill_unavailable" }, 503);
  } finally {
    clearTimeout(timer);
  }
}
