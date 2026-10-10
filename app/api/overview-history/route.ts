import { NextResponse } from "next/server";
import { readPublishedOverviewUsage } from "../../../lib/overview/kpis";
import { readPublishedOverviewActiveCharts } from "../../../lib/overview/active-charts";
import { readPublishedAdoptionSummary } from "../../../lib/overview/adoption";
import { readPublishedWorkflowSummary } from "../../../lib/overview/workflow";
import { readPublishedFrictionSummary } from "../../../lib/overview/friction";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const HEADERS = { "Cache-Control": "private, no-store" };
function reply(data:object,status=200){return NextResponse.json(data,{status,headers:HEADERS});}
function validMonthEnd(value:unknown):value is string{
 if(typeof value!=="string"||!/^2026-(?:0[3-9]|1[0-2])-[0-3]\d$/.test(value))
  return false;
 const [year,month,day]=value.split("-").map(Number);
 const last=new Date(Date.UTC(year,month,0)).getUTCDate();
 return day===last;
}
function istDate(value:string){
 return new Intl.DateTimeFormat("sv-SE",{
  timeZone:"Asia/Kolkata",year:"numeric",month:"2-digit",day:"2-digit",
 }).format(new Date(value));
}
async function lookupHistoryId(asOf:string):Promise<number|null>{
 const url=process.env.SUPABASE_URL;
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)throw new Error("missing_data_credentials");
 const r=await fetch(url+"/rest/v1/rpc/read_overview_history_id_v1",{
  method:"POST",cache:"no-store",signal:AbortSignal.timeout(15_000),
  headers:{apikey:key,Authorization:"Bearer "+key,
   "Content-Type":"application/json","Cache-Control":"no-store"},
  body:JSON.stringify({p_as_of:asOf}),
 });
 if(!r.ok)throw new Error("history_lookup_http_"+r.status);
 const data:unknown=await r.json();
 return typeof data==="number"&&Number.isSafeInteger(data)&&data>0?data:null;
}
export async function POST(request:Request){
 const origin=request.headers.get("origin"),host=request.headers.get("host");
 if(origin){
  try{if(!host||new URL(origin).host!==host)return reply({error:"forbidden_origin"},403);}
  catch{return reply({error:"invalid_origin"},403);}
 }
 let raw:unknown;
 try{raw=await request.json();}catch{return reply({error:"invalid_json"},400);}
 if(!raw||typeof raw!=="object"||Array.isArray(raw))
  return reply({error:"invalid_parameters"},400);
 const asOf=(raw as Record<string,unknown>).as_of;
 if(!validMonthEnd(asOf))return reply({error:"invalid_month_end"},400);
 try{
  const [id,latest]=await Promise.all([lookupHistoryId(asOf),readPublishedOverviewUsage()]);
  if(!id)return reply({error:"history_not_recorded",detail:"Only verified event history is available."},422);
  if(!latest||Date.parse(asOf+"T18:29:59Z")>=Date.parse(latest.asOf))
   return reply({error:"unsupported_reporting_date"},422);
  const [usage,charts,adoption,workflow,friction]=await Promise.all([
   readPublishedOverviewUsage(id),
   readPublishedOverviewActiveCharts(id),
   readPublishedAdoptionSummary(id),
   readPublishedWorkflowSummary(id),
   readPublishedFrictionSummary(id),
  ]);
  const values=[usage,charts,adoption,workflow,friction];
  if(values.some(value=>!value||value.snapshotId!==id||
      istDate(value.asOf)!==asOf || value.sourceWatermarkAt!==usage?.sourceWatermarkAt))
   return reply({error:"historical_snapshot_mismatch"},409);
  const incompleteTracking=(asOf>="2026-05-31"&&asOf<="2026-08-31")
   ||asOf==="2026-03-31";
  return reply({
   contract:"overview_history_v1",as_of_date:asOf,snapshot_id:id,
   source_watermark_at:usage!.sourceWatermarkAt,
   quality_notice:incompleteTracking
    ?"Historical telemetry is incomplete. Use observed activity only, not inferred missing integrations."
    :"Historical values reflect only recorded integration and core events.",
   usage,charts,adoption,workflow,friction,
  });
 }catch(error){
  console.error("overview-history",error instanceof Error?error.message.slice(0,130):"unknown");
  return reply({error:"history_unavailable"},503);
 }
}
