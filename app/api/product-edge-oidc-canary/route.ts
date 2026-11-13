import { NextResponse } from "next/server";

// Temporary migration smoke probe, preview-only and read-only.
// Vercel injects its short-lived project OIDC token on the request.
// Neither the token nor Companies records are returned to the caller.
export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const maxDuration = 30;

const HEADERS = { "Cache-Control": "private, no-store" };
function reply(data: Record<string, unknown>, status: number) {
  return NextResponse.json(data, { status, headers: HEADERS });
}

type EdgeResult = {
  status: number;
  valid: boolean;
  payload: Record<string, unknown> | null;
};

async function readCompanies(token: string, slug: string): Promise<EdgeResult> {
  const response = await fetch(
    `https://hdgbmcerogqfocyxdnpw.supabase.co/functions/v1/${slug}`,
    {
      method: "POST",
      cache: "no-store",
      signal: AbortSignal.timeout(20_000),
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action: "list", page: 1 }),
    },
  );
  const raw: unknown = await response.json();
  const data = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, unknown> : null;
  return {
    status: response.status,
    valid: response.status === 200 &&
      Array.isArray(data?.rows) &&
      typeof data?.total === "number" &&
      data?.page === 1 &&
      data?.page_size === 10 &&
      typeof data?.available === "boolean",
    payload: data,
  };
}

export async function GET(request: Request) {
  if (
    process.env.VERCEL_ENV !== "preview" ||
    process.env.VERCEL_GIT_COMMIT_REF !== "product/numbered-schema-shadow-20261106"
  ) {
    return reply({ error: "not_found" }, 404);
  }
  const token = request.headers.get("x-vercel-oidc-token");
  if (!token) return reply({ passed: false, reason: "managed_vercel_oidc_missing" }, 503);
  try {
    // Sequential calls avoid doubling the expensive usage aggregation load.
    const isolated = await readCompanies(token, "companies-dashboard-product-canary");
    const deployed = await readCompanies(token, "companies-dashboard");
    const same = isolated.valid && deployed.valid &&
      JSON.stringify(isolated.payload) === JSON.stringify(deployed.payload);
    return reply({
      passed: same,
      isolated_status: isolated.status,
      deployed_status: deployed.status,
      isolated_contract_valid: isolated.valid,
      deployed_contract_valid: deployed.valid,
      response_parity: same,
    }, same ? 200 : 502);
  } catch {
    return reply({ passed: false, reason: "upstream_request_failed" }, 502);
  }
}
