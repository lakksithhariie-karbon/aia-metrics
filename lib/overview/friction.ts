/** Observed product friction. Later success means a subsequent event in the
 * same company/workflow, not a verified repair of the original item.
 * Reads only the currently published Overview snapshot. */
export type FrictionKey =
 | "review_reverted" | "bill_upload" | "type_update" | "invoice_upload" | "ledger_update";
export type FrictionPeriod = "current"|"previous";
export type FrictionSegment = "eligible"|"affected"|"later_success"|"needs_review";
export interface FrictionPeriodCounts {
 eligible:number;affected:number;followup:number;needs_review:number;
 incidence_pct:number|null;followup_pct?:number|null;
}
export interface FrictionIssue {
 key:FrictionKey;label:string;module:"Transactions"|"Uploads";
 kind:"Rework"|"Failure";
 current:FrictionPeriodCounts;previous:FrictionPeriodCounts;
 change_pp:number|null;
}
export interface FrictionSummary {
 snapshotId:number;asOf:string;sourceWatermarkAt:string;
 window:{current_start:string;current_end:string;previous_start:string;previous_end:string};
 rows:FrictionIssue[];
}
export interface FrictionUserRow{
 id:string;email:string;attempts:number;failures:number;
 successes:number;last_at:string|null;
}
export interface FrictionCompanyRow{
 id:string;name:string;is_test:boolean;
 eligible_events:number;failed_events:number;success_events:number;
 observed_users:number;
 first_failure_at:string|null;last_failure_at:string|null;
 followup_at:string|null;last_event_at:string|null;
 users:FrictionUserRow[];
}
export interface FrictionCompanyList{
 contract:"observed_company_friction_list_v1";
 snapshot_id:number;as_of:string;source_watermark_at:string;
 issue_key:FrictionKey;period:FrictionPeriod;segment:FrictionSegment;
 segment_total:number;total:number;page:number;page_size:number;
 rows:FrictionCompanyRow[];
}
export interface FrictionCompanyDetail{
 contract:"observed_company_friction_company_v1";
 snapshot_id:number;as_of:string;source_watermark_at:string;
 issue_key:FrictionKey;period:FrictionPeriod;segment:FrictionSegment;
 company:{id:string;name:string;is_test:boolean};
 window:{start:string;end:string;days:28};
 summary:{
  attempts:number;failures:number;successes:number;users:number;
  first_failure_at:string|null;last_failure_at:string|null;
  followup_at:string|null;last_event_at:string|null;
 };
 milestones:{company_created_at:string|null;integration_at:string|null};
 users:Array<FrictionUserRow & {first_at:string|null}>;
 weeks:Array<{
  week_start:string;attempts:number;failures:number;successes:number;active_users:number;
 }>;
 events:Array<{
  at:string;event:string;status:string;is_failure:boolean;is_success:boolean;
  activity_type:string;action:string;user_id:string;email:string;
 }>;
}
const KEYS:FrictionKey[]=[
 "review_reverted","bill_upload","type_update","invoice_upload","ledger_update",
];
function obj(value:unknown):Record<string,unknown>|null{
 return value!==null&&typeof value==="object"&&!Array.isArray(value)
  ?value as Record<string,unknown>:null;
}
function natural(n:unknown):n is number{
 return typeof n==="number"&&Number.isSafeInteger(n)&&n>=0;
}
function percent(n:unknown):n is number{
 return typeof n==="number"&&Number.isFinite(n)&&n>=0&&n<=100;
}
function counts(input:unknown):FrictionPeriodCounts|null{
 const value=obj(input);if(!value)return null;
 if(!natural(value.eligible)||!natural(value.affected)
  ||!natural(value.followup)||!natural(value.needs_review)
  ||value.affected>value.eligible
  ||value.followup+value.needs_review!==value.affected
  ||(value.incidence_pct!==null&&!percent(value.incidence_pct))
  ||(value.followup_pct!==undefined&&value.followup_pct!==null
    &&!percent(value.followup_pct)))return null;
 return {
  eligible:value.eligible,affected:value.affected,
  followup:value.followup,needs_review:value.needs_review,
  incidence_pct:value.incidence_pct as number|null,
  followup_pct:value.followup_pct as number|null|undefined,
 };
}
function credentials(){
 const url=process.env.SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 return url&&key?{url,key}:null;
}
async function rpc<T>(name:string,body:Record<string,unknown>,signal?:AbortSignal):Promise<T|null>{
 const creds=credentials();
 if(!creds)return null;
 const r=await fetch(creds.url+"/rest/v1/rpc/"+name,{
  method:"POST",cache:"no-store",signal:signal??AbortSignal.timeout(32_000),
  headers:{apikey:creds.key,Authorization:"Bearer "+creds.key,
   "Content-Type":"application/json","Cache-Control":"no-store"},
  body:JSON.stringify(body),
 });
 if(!r.ok)throw new Error("overview_friction_http_"+r.status);
 return await r.json() as T|null;
}
export async function readPublishedFrictionSummary(snapshotId?:number):Promise<FrictionSummary|null>{
 const raw=obj(await rpc<unknown>("read_overview_friction_v4",snapshotId==null?{}:{p_snapshot_id:snapshotId}));
 if(!raw||raw.contract!=="observed_company_friction_v1"
  ||!natural(raw.snapshot_id)||typeof raw.as_of!=="string"
  ||Number.isNaN(Date.parse(raw.as_of))
  ||typeof raw.source_watermark_at!=="string"
  ||!Array.isArray(raw.rows)||raw.rows.length!==5)return null;
 const window=obj(raw.window);
 if(!window||!["current_start","current_end","previous_start","previous_end"].every(
  key=>typeof window[key]==="string"&&!Number.isNaN(Date.parse(window[key] as string))
 ))return null;
 const rows:FrictionIssue[]=[];
 const seen=new Set<string>();
 for(const item of raw.rows){
  const row=obj(item);if(!row)return null;
  const current=counts(row.current),previous=counts(row.previous);
  if(typeof row.key!=="string"||!KEYS.includes(row.key as FrictionKey)
   ||seen.has(row.key)||typeof row.label!=="string"
   ||(row.module!=="Transactions"&&row.module!=="Uploads")
   ||(row.kind!=="Rework"&&row.kind!=="Failure")
   ||!current||!previous
   ||(row.change_pp!==null&&(
    typeof row.change_pp!=="number"||!Number.isFinite(row.change_pp)
   )))return null;
  // Zero eligible workflows yield a meaningful unavailable rate, not a fatal error.
  seen.add(row.key);
  rows.push({
   key:row.key as FrictionKey,label:row.label,
   module:row.module,kind:row.kind,
   current,previous,change_pp:row.change_pp as number|null,
  });
 }
 if(seen.size!==KEYS.length)return null;
 return {
  snapshotId:raw.snapshot_id,asOf:raw.as_of,
  sourceWatermarkAt:raw.source_watermark_at,
  window:window as unknown as FrictionSummary["window"],rows,
 };
}
export async function readFrictionCompanies(params:{
 snapshotId:number;issue:FrictionKey;period:FrictionPeriod;segment:FrictionSegment;
 query:string;page:number;pageSize:number;signal?:AbortSignal;
}):Promise<FrictionCompanyList|null>{
 return rpc<FrictionCompanyList>("read_overview_friction_companies_v3",{
  p_snapshot_id:params.snapshotId,p_issue_key:params.issue,
  p_period:params.period,p_segment:params.segment,
  p_query:params.query,p_page:params.page,p_page_size:params.pageSize,
 },params.signal);
}
export async function readFrictionCompanyDetail(params:{
 snapshotId:number;issue:FrictionKey;period:FrictionPeriod;
 segment:FrictionSegment;companyId:string;signal?:AbortSignal;
}):Promise<FrictionCompanyDetail|null>{
 return rpc<FrictionCompanyDetail>("read_overview_friction_company_v3",{
  p_snapshot_id:params.snapshotId,p_issue_key:params.issue,p_period:params.period,
  p_segment:params.segment,p_company_id:params.companyId,
 },params.signal);
}
