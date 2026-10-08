import { NextResponse } from "next/server";
import {
 readFrictionCompanies,readFrictionCompanyDetail,
 type FrictionKey,type FrictionPeriod,type FrictionSegment,
} from "../../../lib/overview/friction";

export const dynamic="force-dynamic";
const headers={"Cache-Control":"private, no-store"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const keys=new Set<FrictionKey>([
 "review_reverted","bill_upload","type_update","invoice_upload","ledger_update",
]);
const periods=new Set<FrictionPeriod>(["current","previous"]);
const segments=new Set<FrictionSegment>([
 "eligible","affected","later_success","needs_review",
]);
function json(body:object,status=200){return NextResponse.json(body,{status,headers});}
export async function POST(request:Request){
 const origin=request.headers.get("origin"),host=request.headers.get("host");
 if(origin){
  try{if(!host||new URL(origin).host!==host)return json({error:"invalid_origin"},403);}
  catch{return json({error:"invalid_origin"},403);}
 }
 let body:Record<string,unknown>;
 try{
  const raw:unknown=await request.json();
  if(!raw||typeof raw!=="object"||Array.isArray(raw))
   return json({error:"invalid_body"},400);
  body=raw as Record<string,unknown>;
 }catch{return json({error:"invalid_body"},400);}
 const id=body.snapshot_id,issue=body.issue,period=body.period,segment=body.segment;
 if(typeof id!=="number"||!Number.isSafeInteger(id)||id<1)
  return json({error:"invalid_snapshot"},400);
 if(typeof issue!=="string"||!keys.has(issue as FrictionKey)
  ||typeof period!=="string"||!periods.has(period as FrictionPeriod)
  ||typeof segment!=="string"||!segments.has(segment as FrictionSegment))
  return json({error:"invalid_selection"},400);
 const params={
  snapshotId:id,issue:issue as FrictionKey,
  period:period as FrictionPeriod,segment:segment as FrictionSegment,
 };
 const controller=new AbortController();
 const timer=setTimeout(()=>controller.abort(),34_000);
 try{
  if(body.action==="list"){
   const page=typeof body.page==="number"&&Number.isFinite(body.page)
    ?Math.max(1,Math.min(10000,Math.floor(body.page))):1;
   const pageSize=typeof body.page_size==="number"&&Number.isFinite(body.page_size)
    ?Math.max(1,Math.min(25,Math.floor(body.page_size))):8;
   const result=await readFrictionCompanies({
    ...params,page,pageSize,query:typeof body.query==="string"?body.query.trim().slice(0,80):"",
    signal:controller.signal,
   });
   return result?json(result):json({error:"snapshot_expired"},409);
  }
  if(body.action==="company"){
   const companyId=body.company_id;
   if(typeof companyId!=="string"||!uuid.test(companyId))
    return json({error:"invalid_company_id"},400);
   const result=await readFrictionCompanyDetail({
    ...params,companyId,signal:controller.signal,
   });
   return result?json(result):json({error:"company_not_in_selected_population"},404);
  }
  return json({error:"invalid_action"},400);
 }catch(error){
  console.error("overview-friction-drill",error instanceof Error?error.message.slice(0,140):"unknown_error");
  return json({error:"friction_drill_unavailable"},503);
 }finally{clearTimeout(timer);}
}
