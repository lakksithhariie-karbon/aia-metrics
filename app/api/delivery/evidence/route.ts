import { NextResponse } from "next/server";
import { VALID_EVIDENCE_SORTS, parseDeliveryFilters, readDeliveryEvidence } from "../../../../lib/delivery/server";

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
  const query=typeof body.search==="string"?body.search:"";
  const sort=typeof body.sort==="string"?body.sort:"created_at";
  const direction=typeof body.direction==="string"?body.direction:"desc";
  const exportAll=body.export===true;
  const limit=exportAll?7000:10;
  if(query.length>120 || !VALID_EVIDENCE_SORTS.some(x=>x===sort) ||
     (direction!=="asc"&&direction!=="desc") || (exportAll&&offset!==0)) {
    return bad(400,"invalid_evidence_filter");
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
    const result=await readDeliveryEvidence(filters,key,snapshot,offset,limit,query,
      sort as import("../../../../lib/delivery/types").DeliveryEvidenceSort,
      direction as "asc"|"desc",exportAll);
    if(exportAll){
      // Sanitize spreadsheet formulas, even though source text is Jira-controlled.
      const safe=(value:unknown):string=>{
        const s=String(value??"");
        const first=s.trimStart().charAt(0);
        const guarded=first!==""&&"=+-@".includes(first)?"\'"+s:s;
        return '"'+guarded.replace(/"/g,'""')+'"';
      };
      const cols=["issue_key","summary","issue_type","created_at","resolved_at","severity",
        "status","priority","module","sub_module","assignee","stage_hours"] as const;
      const lines=[cols.map(safe).join(","),...result.rows.map(row=>
        cols.map(col=>safe(row[col])).join(","))];
      return new Response("\uFEFF"+lines.join("\r\n"),{
        headers:{"Content-Type":"text/csv; charset=utf-8","Cache-Control":"no-store",
          "Content-Disposition":"attachment; filename="+JSON.stringify("jira-"+snapshot+"-"+key.replace(/[^a-z0-9-]/gi,"_")+".csv")},
      });
    }
    return NextResponse.json(result,{headers:{"Cache-Control":"no-store"}});
  } catch(error) {
    console.error("delivery_evidence_unavailable",
      error instanceof Error ? error.message.slice(0,120) : "unknown");
    return bad(503,"verified_evidence_unavailable");
  }
}
