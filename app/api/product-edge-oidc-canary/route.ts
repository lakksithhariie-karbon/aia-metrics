import { NextResponse } from "next/server";

// Temporary, read-only migration smoke probe. Preview deployment only.
// Vercel injects its short-lived project OIDC token on the function request.
// Never expose the token or the upstream Companies response to the caller.
export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const maxDuration = 30;

const HEADERS = { "Cache-Control": "private, no-store" };
function reply(data: Record<string, unknown>, status: number) {
  return NextResponse.json(data, { status, headers: HEADERS });
}

export async function GET(request: Request) {
  if (
    process.env.VERCEL_ENV !== "preview" ||
    process.env.VERCEL_GIT_COMMIT_REF !== "product/numbered-schema-shadow-20261106"
  ) {
    return reply({ error: "not_found" }, 404);
  }

  const token = request.headers.get("x-vercel-oidc-token");
  if (!token) {
    return reply({ passed: false, reason: "managed_vercel_oidc_missing" }, 503);
  }

  try {
    const response = await fetch(
      "https://hdgbmcerogqfocyxdnpw.supabase.co/functions/v1/companies-dashboard-product-canary",
      {
        method: "POST",
        cache: "no-store",
        signal: AbortSignal.timeout(25_000),
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ action: "list", page: 1 }),
      },
    );
    const payload: unknown = await response.json();
    const data = payload && typeof payload === "object" && !Array.isArray(payload)
      ? payload as Record<string, unknown>
      : null;
    const passed = response.status === 200 &&
      Array.isArray(data?.rows) &&
      typeof data?.total === "number" &&
      data?.page === 1 &&
      data?.page_size === 10 &&
      typeof data?.available === "boolean";

    return reply({
      passed,
      upstream_status: response.status,
      valid_companies_contract: passed,
    }, passed ? 200 : 502);
  } catch {
    return reply({ passed: false, reason: "upstream_request_failed" }, 502);
  }
}
