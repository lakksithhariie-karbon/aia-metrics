import { NextResponse } from "next/server";
import {
  readAdoptionCompanyDetail,readAdoptionCompanyList,type AdoptionSegment,
} from "../../../lib/overview/adoption";

export const dynamic="force-dynamic";
const headers={"Cache-Control":"private, no-store"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const segments=new Set<AdoptionSegment>([
 "all","core_7d","not_core_7d","value_28d","not_value_28d",
 "sustained_28d","not_sustained_28d","qualifying_sync",
 "stalled_after_integration","stalled_before_sync",
 "module_ap","module_ar","module_transactions",
 "bill_upload","bill_entity","vendor_mismatch",
 "invoice_upload","invoice_entity","invoice_bulk",
 "statement_upload","transaction_ledger","transaction_status","transaction_type",
]);
function reply(body:object,status=200){
 return NextResponse.json(body,{status,headers});
}
export async function POST(request:Request){
  const origin=request.headers.get("origin");
  const host=request.headers.get("host");
  if(origin){
    try{
      if(!host||new URL(origin).host!==host)return reply({error:"forbidden_origin"},403);
    }catch{
      return reply({error:"invalid_origin"},403);
    }
  }
  let body:Record<string,unknown>;
  try{
    const raw:unknown=await request.json();
    if(!raw||typeof raw!=="object"||Array.isArray(raw))
      return reply({error:"invalid_json"},400);
    body=raw as Record<string,unknown>;
  }catch{
    return reply({error:"invalid_json"},400);
  }
  const snapshotId=body.snapshot_id;
  if(typeof snapshotId!=="number"||!Number.isSafeInteger(snapshotId)||snapshotId<1)
    return reply({error:"invalid_snapshot"},400);
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),34_000);
  try{
    if(body.action==="list"){
      if(typeof body.segment!=="string"||!segments.has(body.segment as AdoptionSegment))
        return reply({error:"invalid_segment"},400);
      const page=typeof body.page==="number"&&Number.isFinite(body.page)
        ?Math.min(10000,Math.max(1,Math.floor(body.page))):1;
      const pageSize=typeof body.page_size==="number"&&Number.isFinite(body.page_size)
        ?Math.min(25,Math.max(1,Math.floor(body.page_size))):8;
      const result=await readAdoptionCompanyList({
        snapshotId,
        segment:body.segment as AdoptionSegment,
        query:typeof body.query==="string"?body.query.trim().slice(0,70):"",
        page,pageSize,signal:controller.signal,
      });
      return result?reply(result):reply({error:"snapshot_expired"},409);
    }
    if(body.action==="company"){
      const companyId=body.company_id;
      if(typeof companyId!=="string"||!uuid.test(companyId))
        return reply({error:"invalid_company"},400);
      const result=await readAdoptionCompanyDetail({
        snapshotId,companyId,signal:controller.signal,
      });
      return result?reply(result):reply({error:"company_unavailable"},404);
    }
    return reply({error:"invalid_action"},400);
  }catch(error){
    console.error("adoption-drill",error instanceof Error?error.message.slice(0,140):"unknown_error");
    return reply({error:"adoption_drill_unavailable"},503);
  }finally{
    clearTimeout(timer);
  }
}
