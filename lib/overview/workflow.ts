/** Canonical Workflow Usage: distinct people by completed week, distinct
 * companies by exclusive workflow combination in adjacent rolling 28d periods.
 * All data is pinned to the currently published Overview snapshot. */
export type WorkflowModule = "ap"|"ar"|"transactions";
export type WorkflowPeriod = "current"|"previous";
export type WorkflowMask = "001"|"100"|"101"|"110"|"111"|"010"|"011"|"000";
export type WorkflowCounts = { ap:number;ar:number;transactions:number };
export interface WorkflowWeek {
 week_start:string;total:number;ap:number;ar:number;transactions:number;
 limited_tracking:boolean;
}
export interface WorkflowMixRow {
 mask:WorkflowMask;current:number;previous:number;
}
export interface WorkflowSummary {
 snapshotId:number;asOf:string;sourceWatermarkAt:string;currentWeek:string;
 weekly:WorkflowWeek[];
 mix:{
  current_start:string;current_end:string;
  previous_start:string;previous_end:string;
  current_total:number;previous_total:number;
  current_multi:number;previous_multi:number;
  rows:WorkflowMixRow[];
 };
}
export interface WorkflowModuleCompany {
 id:string;name:string;is_test:boolean;actions:number;active_days:number;
 last_active_at:string|null;
}
export interface WorkflowModuleUser {
 id:string;email:string;actions:number;active_days:number;
 last_active_at:string|null;companies_count:number;
 companies:WorkflowModuleCompany[];
}
export interface WorkflowModuleUsers {
 contract:"independent_workflow_module_users_v1";
 snapshot_id:number;week_start:string;module:WorkflowModule;
 as_of:string;source_watermark_at:string;
 segment_total:number;total:number;page:number;page_size:number;
 rows:WorkflowModuleUser[];
}
export interface WorkflowMixCompany {
 id:string;name:string;is_test:boolean;mask:WorkflowMask;
 users:number;actions:number;active_days:number;
 last_active_at:string|null;modules:WorkflowCounts;
}
export interface WorkflowMixCompanies {
 contract:"independent_workflow_mix_companies_v1";
 snapshot_id:number;as_of:string;source_watermark_at:string;
 period:WorkflowPeriod;mask:WorkflowMask;
 window_start:string;window_end:string;
 segment_total:number;total:number;page:number;page_size:number;
 rows:WorkflowMixCompany[];
}
export interface WorkflowCompanyDetail {
 contract:"independent_workflow_company_v1";
 snapshot_id:number;as_of:string;source_watermark_at:string;
 scope:"weekly"|WorkflowPeriod;
 selected_module:WorkflowModule|null;
 mask:WorkflowMask|null;
 focus_user_id:string|null;
 company:{id:string;name:string;is_test:boolean};
 window:{start:string;end:string;days:number};
 stats:{core_actions:number;active_users:number;active_days:number;
  first_activity_at:string|null;last_activity_at:string|null;modules:WorkflowCounts};
 milestones:{
  company_created_at:string|null;
  integration_at:string|null;
  last_qualifying_sync_at:string|null;
 };
 users:Array<{
  id:string;email:string;core_actions:number;active_days:number;
  last_active_at:string|null;modules:WorkflowCounts;
 }>;
 weeks:Array<{
  week_start:string;core_actions:number;active_users:number;modules:WorkflowCounts;
 }>;
 recent_events:Array<{
  at:string;event:string;module:WorkflowModule;user_id:string;email:string;
 }>;
}

function object(v:unknown):Record<string,unknown>|null {
 return v!==null&&typeof v==="object"&&!Array.isArray(v)
  ?v as Record<string,unknown>:null;
}
function count(v:unknown):v is number {
 return typeof v==="number"&&Number.isSafeInteger(v)&&v>=0;
}
function date(v:unknown):v is string {
 return typeof v==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(v);
}
function counts(raw:unknown,keys:readonly string[]):Record<string,number>|null{
 const obj=object(raw);
 if(!obj)return null;
 const result:Record<string,number>={};
 for(const key of keys){
  if(!count(obj[key]))return null;
  result[key]=obj[key] as number;
 }
 return result;
}
const MODS=["ap","ar","transactions"];
const MASKS=["001","100","101","110","111","010","011","000"] as const;
function creds(){
 const url=process.env.SUPABASE_URL;
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 return url&&key?{url,key}:null;
}
export async function readPublishedWorkflowSummary(snapshotId?:number):Promise<WorkflowSummary|null>{
 const credential=creds();
 if(!credential)return null;
 const response=await fetch(
  credential.url+"/rest/v1/rpc/read_overview_workflow_charts_v3",{
   method:"POST",cache:"no-store",signal:AbortSignal.timeout(30_000),
   headers:{
    apikey:credential.key,Authorization:"Bearer "+credential.key,
    "Content-Type":"application/json","Cache-Control":"no-store",
   },
   body:JSON.stringify(snapshotId==null?{}:{p_snapshot_id:snapshotId}),
  },
 );
 if(!response.ok)throw new Error("overview_workflow_summary_http_"+response.status);
 const data=object(await response.json());
 if(!data||data.contract!=="independent_workflow_v1"
  ||!count(data.snapshot_id)||!date(data.current_week)
  ||typeof data.as_of!=="string"||Number.isNaN(Date.parse(data.as_of))
  ||typeof data.source_watermark_at!=="string"
  ||!Array.isArray(data.weekly)||data.weekly.length!==12)return null;
 const mix=object(data.mix);
 const currentTotal=count(mix?.current_total),previousTotal=count(mix?.previous_total);
 const currentMulti=count(mix?.current_multi),previousMulti=count(mix?.previous_multi);
 if(!mix||currentTotal===null||previousTotal===null
  ||currentMulti===null||previousMulti===null
  ||currentMulti>currentTotal||previousMulti>previousTotal
  ||!Array.isArray(mix.rows)||mix.rows.length!==8
  ||!["current_start","current_end","previous_start","previous_end"].every(
   key=>typeof mix[key]==="string"&&!Number.isNaN(Date.parse(mix[key] as string))
  ))return null;
 const weekly:WorkflowWeek[]=[];
 for(const item of data.weekly){
  const row=object(item);
  if(!row||!date(row.week_start)||count(row.total)===null
   ||MODS.some(key=>count(row[key])===null)
   ||typeof row.limited_tracking!=="boolean"
   ||MODS.some(key=>(row[key] as number)>(row.total as number)))return null;
  weekly.push({
   week_start:row.week_start,total:row.total as number,
   ap:row.ap as number,ar:row.ar as number,
   transactions:row.transactions as number,
   limited_tracking:row.limited_tracking,
  });
 }
 const rows:WorkflowMixRow[]=[];
 for(let i=0;i<MASKS.length;i++){
  const r=object(mix.rows[i]);
  if(!r||r.mask!==MASKS[i]||count(r.current)===null||count(r.previous)===null)return null;
  rows.push({mask:r.mask as WorkflowMask,current:r.current as number,previous:r.previous as number});
 }
 if(rows.reduce((t,r)=>t+r.current,0)!==currentTotal
  ||rows.reduce((t,r)=>t+r.previous,0)!==previousTotal
  ||rows.filter(r=>r.mask.replaceAll("0","").length>1).reduce((t,r)=>t+r.current,0)!==currentMulti
  ||rows.filter(r=>r.mask.replaceAll("0","").length>1).reduce((t,r)=>t+r.previous,0)!==previousMulti)return null;
 return {
  snapshotId:data.snapshot_id,asOf:data.as_of,
  sourceWatermarkAt:data.source_watermark_at,
  currentWeek:data.current_week,
  weekly,
  mix:{
   current_start:mix.current_start as string,current_end:mix.current_end as string,
   previous_start:mix.previous_start as string,previous_end:mix.previous_end as string,
   current_total:currentTotal,previous_total:previousTotal,
   current_multi:currentMulti,previous_multi:previousMulti,
   rows,
  },
 };
}
async function rpc<T>(name:string,payload:object,signal?:AbortSignal):Promise<T|null>{
 const credential=creds();
 if(!credential)throw new Error("supabase_not_configured");
 const response=await fetch(credential.url+"/rest/v1/rpc/"+name,{
  method:"POST",cache:"no-store",signal,
  headers:{
   apikey:credential.key,Authorization:"Bearer "+credential.key,
   "Content-Type":"application/json","Cache-Control":"no-store",
  },
  body:JSON.stringify(payload),
 });
 if(!response.ok)throw new Error("overview_workflow_drill_http_"+response.status);
 return await response.json() as T|null;
}
export async function readWorkflowModuleUsers(params:{
 snapshotId:number;week:string;module:WorkflowModule;
 query:string;page:number;pageSize:number;signal?:AbortSignal;
}):Promise<WorkflowModuleUsers|null>{
 return rpc<WorkflowModuleUsers>("read_overview_workflow_module_users_v3",{
  p_snapshot_id:params.snapshotId,p_week:params.week,p_module:params.module,
  p_query:params.query,p_page:params.page,p_page_size:params.pageSize,
 },params.signal);
}
export async function readWorkflowMixCompanies(params:{
 snapshotId:number;period:WorkflowPeriod;mask:WorkflowMask;
 query:string;page:number;pageSize:number;signal?:AbortSignal;
}):Promise<WorkflowMixCompanies|null>{
 return rpc<WorkflowMixCompanies>("read_overview_workflow_mix_companies_v3",{
  p_snapshot_id:params.snapshotId,p_period:params.period,p_mask:params.mask,
  p_query:params.query,p_page:params.page,p_page_size:params.pageSize,
 },params.signal);
}
export async function readWorkflowCompanyDetail(params:{
 snapshotId:number;scope:"weekly"|WorkflowPeriod;companyId:string;
 week?:string;module?:WorkflowModule;mask?:WorkflowMask;
 userId?:string;signal?:AbortSignal;
}):Promise<WorkflowCompanyDetail|null>{
 return rpc<WorkflowCompanyDetail>("read_overview_workflow_company_v3",{
  p_snapshot_id:params.snapshotId,p_scope:params.scope,p_company_id:params.companyId,
  p_week:params.week??"",p_module:params.module??"",p_mask:params.mask??"",
  p_user_id:params.userId??"",
 },params.signal);
}
