import { NextResponse } from "next/server";
import {
  readActivationCompanyDetail,
  readActivationPreviewList,
} from "../../../lib/retention/drill";

function validDate(value: unknown): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error("invalid_date");
  }
  return value;
}

export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);

  try {
    if (body.action === "list") {
      let from: string | null;
      let to: string | null;
      try {
        from = validDate(body.from);
        to = validDate(body.to);
      } catch {
        return NextResponse.json(
          { error: "invalid_parameters" },
          { status: 400 },
        );
      }

      const status =
        body.status === "activated" ||
        body.status === "awaiting_sync" ||
        body.status === "no_core" ||
        body.status === "no_training"
          ? body.status
          : "all";
      const page =
        typeof body.page === "number" && Number.isFinite(body.page)
          ? Math.max(1, Math.floor(body.page))
          : 1;
      const pageSize =
        typeof body.page_size === "number" && Number.isFinite(body.page_size)
          ? Math.min(50, Math.max(1, Math.floor(body.page_size)))
          : 8;

      const payload = await readActivationPreviewList({
        from,
        to,
        query: typeof body.query === "string" ? body.query : "",
        status,
        page,
        pageSize,
        signal: controller.signal,
      });
      return NextResponse.json(payload);
    }

    if (body.action === "company") {
      if (typeof body.company_id !== "string" || !body.company_id) {
        return NextResponse.json(
          { error: "invalid_parameters" },
          { status: 400 },
        );
      }

      const payload = await readActivationCompanyDetail({
        companyId: body.company_id,
        signal: controller.signal,
      });
      return NextResponse.json(payload);
    }

    return NextResponse.json({ error: "invalid_action" }, { status: 400 });
  } catch (error) {
    const signal = error instanceof Error ? error.message : String(error);
    console.error("retention-drill", signal.slice(0, 240));
    if (signal === "supabase_unavailable") {
      return NextResponse.json(
        { error: "bridge_unavailable" },
        { status: 503 },
      );
    }
    return NextResponse.json(
      { error: "retention_drill_unavailable" },
      { status: 503 },
    );
  } finally {
    clearTimeout(timeout);
  }
}
