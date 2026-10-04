import { NextResponse } from "next/server";
import { companyBreakdown, listCompanies } from "../../../lib/companies/server";
import type { ModuleKey, SortDirection, SortKey, UsageFilter } from "../../../lib/companies/types";

const MODULES = ["ap", "ar", "transactions", "gst", "sync"] as const;

function validSort(value: unknown): SortKey {
  return value === "name" || (MODULES as readonly string[]).includes(String(value))
    ? (value as SortKey)
    : "name";
}

export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (body.action !== "list" && body.action !== "breakdown") {
    return NextResponse.json({ error: "invalid_action" }, { status: 400 });
  }

  const from = typeof body.from === "string" && body.from ? body.from : null;
  const to = typeof body.to === "string" && body.to ? body.to : null;
  const controller = new AbortController();
  // Lifetime aggregates scan the full warehouse; allow headroom while still
  // failing closed on hangs. No fixture fallback on any failure path.
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    if (body.action === "list") {
      const payload = await listCompanies({
        page: Math.max(1, Number(body.page) || 1),
        query: typeof body.query === "string" ? body.query : "",
        integration: typeof body.integration === "string" ? body.integration : "all",
        usage: (["all", "active", "inactive"] as const).includes(body.usage as UsageFilter)
          ? (body.usage as UsageFilter)
          : "all",
        sort: validSort(body.sort),
        direction: body.direction === "desc" ? ("desc" as SortDirection) : ("asc" as SortDirection),
        from,
        to,
      });
      return NextResponse.json(payload);
    }
    const module = typeof body.module === "string" ? body.module : "";
    if (typeof body.company_id !== "string" || !body.company_id || !MODULES.includes(module as ModuleKey)) {
      return NextResponse.json({ error: "invalid_parameters" }, { status: 400 });
    }
    const payload = await companyBreakdown({
      company_id: body.company_id,
      user_id: body.user_id == null ? null : String(body.user_id),
      module: module as ModuleKey,
      from,
      to,
    });
    return NextResponse.json(payload);
  } catch (error) {
    const signal = error instanceof Error ? error.message : String(error);
    if (signal === "supabase_unavailable") {
      return NextResponse.json({ error: "bridge_unavailable" }, { status: 503 });
    }
    return NextResponse.json({ error: "companies_data_unavailable" }, { status: 503 });
  } finally {
    clearTimeout(timeout);
  }
}
