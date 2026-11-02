import { NextRequest, NextResponse } from "next/server";
import { readBillDashboard, readBillEvidence, validateScope, ensurePreviewOnly } from "../../../../lib/ai-services/live";
import type { LiveScope } from "../../../../lib/ai-services/live";

export const dynamic = "force-dynamic";
export const preferredRegion = "bom1";
export const maxDuration = 45;
function fail(error: unknown) {
  const message = error instanceof Error ? error.message : "unknown_error";
  const invalid = message.startsWith("bill_invalid_") || message.includes("invalid_evidence_request");
  // Never log source customer data, API keys, or submitted search text.
  console.error("bill_reporting_unavailable",message.slice(0,110));
  return NextResponse.json({error:invalid?"Invalid filter selection":"Verified bill extraction data unavailable"},{status:invalid?400:503,headers:{"Cache-Control":"no-store"}});
}
function scopeFromParams(url: URL): LiveScope {
  const q=url.searchParams;
  return validateScope({
    from:q.get("from"),to:q.get("to"),scopes:q.getAll("scope"),
    doc:q.get("doc")??"all",status:q.get("status")??"all",search:q.get("search")??"",
  });
}
export async function GET(req: NextRequest) {
  try {
    ensurePreviewOnly();
    const data=await readBillDashboard(scopeFromParams(req.nextUrl));
    return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
  }catch(error){return fail(error);}
}
export async function POST(req: NextRequest) {
  try {
    ensurePreviewOnly();
    const origin=req.headers.get("origin");
    if(origin && origin!==req.nextUrl.origin) return NextResponse.json({error:"Forbidden"},{status:403});
    const body: unknown=await req.json();
    if(!body || typeof body!=="object" || Array.isArray(body))throw new Error("bill_invalid_body");
    const b=body as Record<string,unknown>;
    const data=await readBillEvidence(validateScope(b.scope),b);
    return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
  }catch(error){return fail(error);}
}
