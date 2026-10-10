import { NextResponse } from "next/server";
import { parseDeliveryFilters, readDeliveryIssue } from "../../../../lib/delivery/server";

export const dynamic = "force-dynamic";
export const maxDuration = 40;

const fail=(status:number,error:string)=>NextResponse.json({error},{
  status,headers:{"Cache-Control":"no-store"},
});

export async function POST(request:Request){
  let body:Record<string,unknown>;
  try{
    const raw:unknown=await request.json();
    if(!raw||typeof raw!=="object"||Array.isArray(raw))return fail(400,"invalid_request");
    body=raw as Record<string,unknown>;
  }catch{return fail(400,"invalid_json");}
  if(typeof body.issue_key!=="string"||typeof body.key!=="string"||
     typeof body.snapshot_id!=="number"||
     !Number.isSafeInteger(body.snapshot_id)||
     typeof body.filters!=="object"||!body.filters||Array.isArray(body.filters)) {
    return fail(400,"invalid_issue_request");
  }
  const f=body.filters as Record<string,unknown>;
  const str=(value:unknown)=>typeof value==="string"?value:undefined;
  try{
    const filters=parseDeliveryFilters({
      sprint:f.sprint==null?undefined:String(f.sprint),
      module:str(f.module),sub_module:str(f.sub_module),
      severity:str(f.severity),assignee:str(f.assignee),
    });
    const detail=await readDeliveryIssue(filters,body.key,body.issue_key,body.snapshot_id);
    return NextResponse.json(detail,{headers:{"Cache-Control":"no-store"}});
  }catch(error){
    console.error("delivery_issue_unavailable",
      error instanceof Error?error.message.slice(0,120):"unknown");
    return fail(503,"verified_issue_detail_unavailable");
  }
}
