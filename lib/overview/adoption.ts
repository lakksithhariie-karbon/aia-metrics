export type AdoptionOutcome = "core_7d" | "value_28d" | "sustained_28d";
export type AdoptionStage = "integration" | "started_work" | "qualifying_sync";
export type AdoptionModule = "ap" | "ar" | "transactions";
export type AdoptionStep = "bill_upload" | "bill_entity" | "vendor_mismatch" |
  "invoice_upload" | "invoice_entity" | "invoice_bulk" |
  "statement_upload" | "transaction_ledger" | "transaction_status" | "transaction_type";
export type AdoptionSegment =
  | "all" | "core_7d" | "not_core_7d" | "value_28d" | "not_value_28d"
  | "sustained_28d" | "not_sustained_28d" | "qualifying_sync"
  | "stalled_after_integration" | "stalled_before_sync"
  | "module_ap" | "module_ar" | "module_transactions" | AdoptionStep;
export type ModuleCounts = { ap:number; ar:number; transactions:number };

export interface AdoptionSummary {
  snapshotId: number;
  asOf: string;
  sourceWatermarkAt: string;
  cohortStart: string;
  cohortEnd: string;
  total: number;
  outcomes: Record<AdoptionOutcome,number>;
  stages: Record<AdoptionStage,number>;
  modules: Record<AdoptionModule,number>;
  steps: Record<AdoptionStep,number>;
}
export interface AdoptionUser {
  id:string;email:string;core_actions:number;
  last_core_at:string|null;modules:ModuleCounts;
}
export interface AdoptionCompany {
  id:string;name:string;integration_type:string;is_test:boolean;
  integration_at:string;
  first_core_7d_at:string|null;first_core_28d_at:string|null;
  sync_after_core_at:string|null;value_at:string|null;
  active_weeks:number;core_actions:number;last_core_at:string|null;
  modules:ModuleCounts;users:AdoptionUser[];
}
export interface AdoptionList {
  contract:"mature_independent_adoption_companies_v1";
  snapshot_id:number;source_watermark_at:string;as_of:string;
  segment:AdoptionSegment;segment_total:number;total:number;
  page:number;page_size:number;rows:AdoptionCompany[];
}
export interface AdoptionCompanyDetail {
  contract:"mature_independent_adoption_company_v1";
  snapshot_id:number;source_watermark_at:string;as_of:string;
  company:{id:string;name:string;integration_type:string;is_test:boolean};
  window:{start:string;end:string;days:28};
  outcomes:Record<AdoptionOutcome| "sync_after_core",boolean>;
  stats:{
    core_actions:number;sync_events:number;active_weeks:number;
    active_users:number;last_core_at:string|null;modules:ModuleCounts;
  };
  milestones:{
    integration_at:string;first_core_7d_at:string|null;
    first_core_28d_at:string|null;training_sync_at:string|null;
    post_training_core_at:string|null;sync_after_core_at:string|null;
    value_at:string|null;
  };
  users:Array<AdoptionUser & {
    sync_events:number;core_days:number;
    first_core_at:string|null;
  }>;
  weeks:Array<{
    week:number;start:string;core_actions:number;
    active_users:number;sync_events:number;modules:ModuleCounts;
  }>;
  recent_events:Array<{
    at:string;event:string;module:"ap"|"ar"|"transactions"|"sync";
    email:string;user_id:string;
  }>;
}
type JsonObject=Record<string,unknown>;
function asObject(v:unknown):JsonObject|null{
  return v!==null&&typeof v==="object"&&!Array.isArray(v) ? v as JsonObject : null;
}
function count(v:unknown):number|null{
  return typeof v==="number"&&Number.isSafeInteger(v)&&v>=0?v:null;
}
function checkCounts(v:unknown,keys:readonly string[]): Record<string,number>|null {
  const o=asObject(v);if(!o)return null;
  const result:Record<string,number>={};
  for(const key of keys){const n=count(o[key]);if(n===null)return null;result[key]=n;}
  return result;
}
const OUTCOME_KEYS=["core_7d","value_28d","sustained_28d"] as const;
const STAGE_KEYS=["integration","started_work","qualifying_sync"] as const;
const MODULE_KEYS=["ap","ar","transactions"] as const;
const STEP_KEYS=[
  "bill_upload","bill_entity","vendor_mismatch",
  "invoice_upload","invoice_entity","invoice_bulk",
  "statement_upload","transaction_ledger","transaction_status","transaction_type",
] as const;

function credentials(){
  const url=process.env.SUPABASE_URL;
  const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  return url&&key?{url,key}:null;
}
async function rpc<T>(name:string,body:Record<string,unknown>,signal?:AbortSignal):Promise<T|null>{
  const creds=credentials();
  if(!creds)return null;
  const response=await fetch(creds.url+"/rest/v1/rpc/"+name,{
    method:"POST",cache:"no-store",
    signal:signal??AbortSignal.timeout(30_000),
    headers:{
      apikey:creds.key,Authorization:"Bearer "+creds.key,
      "Content-Type":"application/json","Cache-Control":"no-store",
    },
    body:JSON.stringify(body),
  });
  if(!response.ok)throw new Error("adoption_rpc_"+name+"_"+response.status);
  return await response.json() as T|null;
}
export async function readPublishedAdoptionSummary():Promise<AdoptionSummary|null>{
  const raw=asObject(await rpc<unknown>("read_overview_adoption_journey_v2",{}));
  if(!raw||raw.contract!=="mature_independent_adoption_v1")return null;
  const snapshotId=count(raw.snapshot_id),total=count(raw.total);
  const outcomes=checkCounts(raw.outcomes,OUTCOME_KEYS);
  const stages=checkCounts(raw.stages,STAGE_KEYS);
  const modules=checkCounts(raw.modules,MODULE_KEYS);
  const steps=checkCounts(raw.steps,STEP_KEYS);
  if(snapshotId===null||total===null||!outcomes||!stages||!modules||!steps||
    stages.integration!==total||stages.started_work!==outcomes.core_7d||
    stages.qualifying_sync>stages.started_work||
    outcomes.value_28d>total||outcomes.sustained_28d>total||
    modules.ap>stages.started_work||modules.ar>stages.started_work||
    modules.transactions>stages.started_work||
    typeof raw.as_of!=="string"||Number.isNaN(Date.parse(raw.as_of))||
    typeof raw.source_watermark_at!=="string"||
    typeof raw.cohort_start!=="string"||typeof raw.cohort_end!=="string")return null;
  return {
    snapshotId,asOf:raw.as_of,sourceWatermarkAt:raw.source_watermark_at,
    cohortStart:raw.cohort_start,cohortEnd:raw.cohort_end,total,
    outcomes:outcomes as Record<AdoptionOutcome,number>,
    stages:stages as Record<AdoptionStage,number>,
    modules:modules as Record<AdoptionModule,number>,
    steps:steps as Record<AdoptionStep,number>,
  };
}
export async function readAdoptionCompanyList(params:{
 snapshotId:number;segment:AdoptionSegment;query:string;
 page:number;pageSize:number;signal?:AbortSignal;
}):Promise<AdoptionList|null>{
 return rpc<AdoptionList>("read_overview_adoption_companies_v2",{
  p_snapshot_id:params.snapshotId,p_segment:params.segment,p_query:params.query,
  p_page:params.page,p_page_size:params.pageSize,
 },params.signal);
}
export async function readAdoptionCompanyDetail(params:{
 snapshotId:number;companyId:string;signal?:AbortSignal;
}):Promise<AdoptionCompanyDetail|null>{
 return rpc<AdoptionCompanyDetail>("read_overview_adoption_company_v2",{
  p_snapshot_id:params.snapshotId,p_company_id:params.companyId,
 },params.signal);
}
