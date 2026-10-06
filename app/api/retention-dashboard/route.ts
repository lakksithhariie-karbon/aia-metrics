import { NextResponse } from "next/server";
import { readRetentionDashboardPreviewV4 } from "../../../lib/retention/server";

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

  let from: string | null;
  let to: string | null;
  try {
    from = validDate(body.from);
    to = validDate(body.to);
  } catch {
    return NextResponse.json({ error: "invalid_parameters" }, { status: 400 });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);

  try {
    const payload = await readRetentionDashboardPreviewV4({
      from,
      to,
      signal: controller.signal,
    });
    return NextResponse.json(payload);
  } catch (error) {
    const signal = error instanceof Error ? error.message : String(error);
    console.error("retention-dashboard-api", signal.slice(0, 200));
    if (signal === "supabase_unavailable") {
      return NextResponse.json(
        { error: "bridge_unavailable" },
        { status: 503 },
      );
    }
    return NextResponse.json(
      { error: "retention_dashboard_unavailable" },
      { status: 503 },
    );
  } finally {
    clearTimeout(timeout);
  }
}
