import { NextResponse } from "next/server";

const DATA_URL = process.env.COMPANIES_DATA_URL ??
  "https://hdgbmcerogqfocyxdnpw.supabase.co/functions/v1/companies-dashboard";

function allowedAction(value: unknown): value is "list" | "breakdown" {
  return value === "list" || value === "breakdown";
}

export async function POST(request: Request) {
  const oidc = process.env.VERCEL_OIDC_TOKEN;
  if (!oidc) {
    return NextResponse.json({ error: "companies_data_unavailable" }, { status: 503 });
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

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
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
    return NextResponse.json({ error: "companies_data_unavailable" }, { status: 503 });
  } finally {
    clearTimeout(timeout);
  }
}
