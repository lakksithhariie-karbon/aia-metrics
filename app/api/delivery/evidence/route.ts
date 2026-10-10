import { NextResponse } from "next/server";
import { parseDeliveryFilters, readDeliveryEvidence } from "../../../../lib/delivery/server";

export const dynamic = "force-dynamic";
export const maxDuration = 35;

const bad = (status: number, error: string) =>
  NextResponse.json({ error }, { status, headers: { "Cache-Control": "no-store" } });

export async function POST(request: Request) {
  let body: Record<string,unknown>;
  try {
    const decoded: unknown = await request.json();
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      return bad(400,"invalid_request");
    }
    body = decoded as Record<string,unknown>;
  } catch { return bad(400,"invalid_json"); }

  const key = body.key;
  const snapshot = body.snapshot_id;
  const offset = body.offset;
  const filterInput = body.filters;
  if (typeof key !== "string" || key.length>90 || key.length===0 ||
      typeof snapshot !== "number" || !Number.isSafeInteger(snapshot) ||
      typeof offset !== "number" || !Number.isSafeInteger(offset) ||
      offset<0 || offset>25000 ||
      typeof filterInput !== "object" || filterInput === null ||
      Array.isArray(filterInput)) {
    return bad(400,"invalid_request");
  }
  try {
    const input = filterInput as Record<string,unknown>;
    const value = (v:unknown) => typeof v === "string" ? v : undefined;
    const raw = {
      sprint: input.sprint == null ? undefined : String(input.sprint),
      module: value(input.module),
      sub_module: value(input.sub_module),
      severity: value(input.severity),
      assignee: value(input.assignee),
    };
    const filters = parseDeliveryFilters(raw);
    const result=await readDeliveryEvidence(filters,key,snapshot,offset);
    return NextResponse.json(result,{headers:{"Cache-Control":"no-store"}});
  } catch(error) {
    console.error("delivery_evidence_unavailable",
      error instanceof Error ? error.message.slice(0,120) : "unknown");
    return bad(503,"verified_evidence_unavailable");
  }
}
