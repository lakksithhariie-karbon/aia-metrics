import { NextResponse } from "next/server";
import {
 readWorkflowModuleUsers,readWorkflowMixCompanies,readWorkflowCompanyDetail,
 type WorkflowModule,type WorkflowPeriod,type WorkflowMask,
} from "../../../lib/overview/workflow";

export const dynamic="force-dynamic";
const headers={"Cache-Control":"private, no-store"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const masks=new Set<WorkflowMask>([
 "001","100","101","110","111","010","011","000",
]);
const modules=new Set<WorkflowModule>(["ap","ar","transactions"]);
function send(body:object,status=200){
 return NextResponse.json(body,{status,headers});
}
export async function POST(request:Request){
 const origin=request.headers.get("origin");
 const host=request.headers.get("host");
 if(origin){
  try{
   if(!host||new URL(origin).host!==host)return send({error:"invalid_origin"},403);
  }catch{return send({error:"invalid_origin"},403);}
 }
 let body:Record<string,unknown>;
 try{
  const raw:unknown=await request.json();
  if(!raw||typeof raw!=="object"||Array.isArray(raw))
   return send({error:"invalid_body"},400);
  body=raw as Record<string,unknown>;
 }catch{return send({error:"invalid_body"},400);}
 const id=body.snapshot_id;
 if(typeof id!=="number"||!Number.isSafeInteger(id)||id<1)
  return send({error:"invalid_snapshot"},400);
 const action=body.action;
 const page=typeof body.page==="number"&&Number.isFinite(body.page)
  ?Math.max(1,Math.min(10000,Math.floor(body.page))):1;
 const pageSize=typeof body.page_size==="number"&&Number.isFinite(body.page_size)
  ?Math.max(1,Math.min(25,Math.floor(body.page_size))):10;
 const query=typeof body.query==="string"?body.query.trim().slice(0,80):"";
 const module=body.module;
 const mask=body.mask;
 const period=body.period;
 const week=body.week;
 const validModule=typeof module==="string"&&modules.has(module as WorkflowModule);
 const validMask=typeof mask==="string"&&masks.has(mask as WorkflowMask);
 const validPeriod=period==="current"||period==="previous";
 const validWeek=typeof week==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(week)
   && !Number.isNaN(Date.parse(week+"T00:00:00Z"))
   && new Date(week+"T00:00:00Z").toISOString().slice(0,10)===week;
 const controller=new AbortController();
 const timer=setTimeout(()=>controller.abort(),34_000);
 try{
  if(action==="module_users"){
   if(!validModule||!validWeek)return send({error:"invalid_module_or_week"},400);
   const result=await readWorkflowModuleUsers({
    snapshotId:id,week,module:module as WorkflowModule,
    query,page,pageSize,signal:controller.signal,
   });
   return result?send(result):send({error:"snapshot_expired"},409);
  }
  if(action==="mix_companies"){
   if(!validMask||!validPeriod)return send({error:"invalid_mask_or_period"},400);
   const result=await readWorkflowMixCompanies({
    snapshotId:id,period:period as WorkflowPeriod,mask:mask as WorkflowMask,
    query,page,pageSize,signal:controller.signal,
   });
   return result?send(result):send({error:"snapshot_expired"},409);
  }
  if(action==="company"){
   const companyId=body.company_id;
   const scope=body.scope;
   const userId=body.user_id;
   if(typeof companyId!=="string"||!uuid.test(companyId))
    return send({error:"invalid_company"},400);
   const isWeek=scope==="weekly";
   if(isWeek){
    if(!validWeek||!validModule||typeof userId!=="string"||!uuid.test(userId))
     return send({error:"invalid_company_context"},400);
   }else if((scope!=="current"&&scope!=="previous")||!validMask){
    return send({error:"invalid_company_context"},400);
   }
   const result=await readWorkflowCompanyDetail({
    snapshotId:id,
    scope:scope as "weekly"|WorkflowPeriod,companyId,
    week:isWeek?week as string:"",
    module:isWeek?module as WorkflowModule:undefined,
    mask:!isWeek?mask as WorkflowMask:undefined,
    userId:isWeek?userId as string:"",
    signal:controller.signal,
   });
   return result?send(result):send({error:"company_not_in_selected_population"},404);
  }
  return send({error:"invalid_action"},400);
 }catch(error){
  console.error("overview-workflow-drill",error instanceof Error?error.message.slice(0,135):"unknown");
  return send({error:"workflow_drill_unavailable"},503);
 }finally{clearTimeout(timer);}
}
