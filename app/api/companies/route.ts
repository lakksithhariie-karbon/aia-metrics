import { NextResponse } from "next/server";

const DATA_URL = process.env.COMPANIES_DATA_URL ??
  "https://hdgbmcerogqfocyxdnpw.supabase.co/functions/v1/companies-dashboard";

function allowedAction(value: unknown): value is "list" | "breakdown" {
  return value === "list" || value === "breakdown";
}

export async function POST(request: Request) {
  const oidc = process.env.VERCEL_OIDC_TOKEN;
  if (!oidc) {
    // Distinct code (not data status): the deployment exposes no OIDC token.
    return NextResponse.json({ error: "oidc_unavailable" }, { status: 503 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!allowedAction(body.action)) {
    return NextResponse.json({ error: "invalid_action" }, { status: 400 });
  }

  // Lifetime aggregates scan the full warehouse; the bridge answers in a few
  // seconds, so allow headroom while still failing closed on hangs.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const response = await fetch(DATA_URL, {
      method: "POST",
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${oidc}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const payload = await response.json().catch(() => ({ error: "invalid_upstream_response" }));
    return NextResponse.json(payload, { status: response.status });
  } catch {
    // Distinct code: the bridge call itself failed (network/abort), as
    // opposed to the bridge reporting a data problem.
    return NextResponse.json({ error: "upstream_unreachable" }, { status: 503 });
  } finally {
    clearTimeout(timeout);
  }
}
