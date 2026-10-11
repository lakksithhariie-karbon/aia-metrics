"use client";

import type { DeliveryEvidence, DeliveryEvidenceSort, DeliveryFilters } from "../../lib/delivery/types";

export type EvidenceSort = DeliveryEvidenceSort | "age_days";
export type EvidenceRequest = {
  key:string;snapshot_id:number;filters:DeliveryFilters;
  expected_count?:number;offset:number;search:string;
  sort:EvidenceSort;direction:"asc"|"desc";
};

// First-page-only intent prefetch. Scoped to a verified snapshot and every
// filter dimension. No persistent storage, cross-user cache or stale fallback.
const FIRST_PAGE_TTL_MS=20_000;
const MAX_ENTRIES=24;
const firstPage=new Map<string,{until:number;promise:Promise<DeliveryEvidence>}>();
const dbSort:Record<DeliveryEvidenceSort,string>={
  issue_key:"key",created_at:"created",resolved_at:"resolved",
  severity:"severity",status:"status",priority:"priority",assignee:"assignee",
};
function identity(request:EvidenceRequest):string{
  const f=request.filters;
  return JSON.stringify([
    request.snapshot_id,request.key,f.sprint,f.module,f.sub_module,
    f.severity,f.assignee,request.expected_count??null,request.offset,
    request.search,request.sort,request.direction,
  ]);
}
function isFirstPage(request:EvidenceRequest):boolean{
  return request.offset===0&&request.search===""&&
    request.sort==="created_at"&&request.direction==="desc";
}
async function requestPage(request:EvidenceRequest,signal?:AbortSignal):Promise<DeliveryEvidence>{
  const response=await fetch("/api/delivery/evidence",{
    method:"POST",cache:"no-store",signal,
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify(request),
  });
  if(!response.ok)throw Error("evidence_request_failed");
  const result=await response.json() as DeliveryEvidence;
  const expectedSort=request.sort==="age_days"?"age_days":dbSort[request.sort];
  if(result.contract!=="jira_delivery_evidence_v2"||
     result.key!==request.key||result.snapshot_id!==request.snapshot_id||
     result.offset!==request.offset||result.limit!==10||
     result.query!==request.search||result.sort!==expectedSort||
     result.direction!==request.direction||
     !Number.isSafeInteger(result.total)||result.total<0||
     !Number.isSafeInteger(result.source_count)||result.source_count<0||
     !Array.isArray(result.rows)||result.rows.length>10||
     result.rows.length!==Math.max(0,Math.min(10,result.total-request.offset))||
     (request.expected_count!==undefined&&result.source_count!==request.expected_count)){
    throw Error("evidence_contract_mismatch");
  }
  return result;
}
export function loadEvidencePage(request:EvidenceRequest,signal?:AbortSignal):Promise<DeliveryEvidence>{
  if(!isFirstPage(request))return requestPage(request,signal);
  const key=identity(request);
  const previous=firstPage.get(key);
  if(previous&&previous.until>Date.now())return previous.promise;
  firstPage.delete(key);
  // A hover request keeps running if the pointer click mounts the modal.
  const pending=requestPage(request);
  const verified=pending.catch(error=>{
    if(firstPage.get(key)?.promise===verified)firstPage.delete(key);
    throw error;
  });
  firstPage.set(key,{until:Date.now()+FIRST_PAGE_TTL_MS,promise:verified});
  while(firstPage.size>MAX_ENTRIES){
    const oldest=firstPage.keys().next().value;
    if(oldest===undefined)break;
    firstPage.delete(oldest);
  }
  return verified;
}
export function prefetchEvidencePage(request:EvidenceRequest):void{
  void loadEvidencePage(request).catch(()=>{ /* Error is handled in the opened modal. */ });
}
