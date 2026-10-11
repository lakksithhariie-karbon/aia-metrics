import { readDeliveryDashboard, readAssigneeMatrixEvidence } from "./server";
import type { DeliveryEvidenceItem, DeliveryFilters, SprintRow } from "./types";

// Use the already audited and service-role-only Jira cohorts. The client gets
// aggregated counts, never the full issue population at page load.
export const UNTAGGED_MODULE="__untagged__";
export const moduleKey=(v:string|null|undefined):string=>v?.trim()||UNTAGGED_MODULE;
export const assigneeKey=(v:string|null|undefined):string=>v?.trim()||"__unassigned__";
export const typeKey=(v:string|null|undefined):string=>v?.trim()||"Unspecified";

export type MatrixCounts={
  open:number;stale:number;blocked:number;modules:Record<string,number>;
};
export type AssigneeRow=MatrixCounts&{
  key:string;name:string;
  types:Array<MatrixCounts&{type:string}>;
};
export type AssigneeMatrix={
  snapshot_id:number;synced_at:string;
  filters:DeliveryFilters;
  totals:MatrixCounts&{assignees:number;untagged:number};
  assignees:AssigneeRow[];
  modules:Array<{key:string;name:string;count:number}>;
  options:{sprints:Array<Pick<SprintRow,"sprint_id"|"sprint_name"|"state">>;
    modules:string[];sub_modules:string[];severities:string[]};
};
const count=(v:unknown):v is number=>typeof v==="number"&&Number.isSafeInteger(v)&&v>=0;
const empty=():MatrixCounts=>({open:0,stale:0,blocked:0,modules:{}});
function add(c:MatrixCounts,module:string,isStale:boolean,isBlocked:boolean){
  c.open++;
  c.modules[module]=(c.modules[module]??0)+1;
  if(isStale)c.stale++;
  if(isBlocked)c.blocked++;
}
export async function readAssigneeMatrix(filters:DeliveryFilters):Promise<AssigneeMatrix>{
  // Remove the dashboard -> evidence waterfall. Every independent reader
  // enforces the live published snapshot gate; cross-reader snapshot parity
  // is checked below before returning any matrix data.
  const [dashboard,open,stale,blocked]=await Promise.all([
    readDeliveryDashboard(filters),
    readAssigneeMatrixEvidence(filters,"wip_open"),
    readAssigneeMatrixEvidence(filters,"stale_7d"),
    readAssigneeMatrixEvidence(filters,"blocked"),
  ]);
  const snapshot=dashboard.snapshot_id;
  const cohorts=[
    [open,"wip_open",dashboard.flow.flow_counts.open_total],
    [stale,"stale_7d",dashboard.flow.flow_counts.stale_all],
    [blocked,"blocked",dashboard.flow.flow_counts.blocked_all],
  ] as const;
  for(const [value,key,total] of cohorts){
    if(value.snapshot_id!==snapshot||value.key!==key||
       !count(value.total)||value.total!==total||
       value.source_count!==value.total||
       value.rows.length!==value.total||
       new Set(value.rows.map(row=>row.issue_key)).size!==value.total){
      throw Error("jira_assignee_matrix_cohort_mismatch_"+key);
    }
  }
  const keys=new Set(open.rows.map(row=>row.issue_key));
  const staleKeys=new Set(stale.rows.map(row=>row.issue_key));
  const blockedKeys=new Set(blocked.rows.map(row=>row.issue_key));
  if([...staleKeys,...blockedKeys].some(key=>!keys.has(key))){
    throw Error("jira_assignee_matrix_membership_mismatch");
  }
  const owners=new Map<string,{
    counts:MatrixCounts;
    types:Map<string,MatrixCounts>;
  }>();
  const totals=empty();
  const modules=new Map<string,number>();
  for(const issue of open.rows as DeliveryEvidenceItem[]){
    const person=assigneeKey(issue.assignee);
    const module=moduleKey(issue.module);
    const kind=typeKey(issue.issue_type);
    const s=staleKeys.has(issue.issue_key),b=blockedKeys.has(issue.issue_key);
    let entry=owners.get(person);
    if(!entry){entry={counts:empty(),types:new Map()};owners.set(person,entry);}
    let type=entry.types.get(kind);
    if(!type){type=empty();entry.types.set(kind,type);}
    add(entry.counts,module,s,b);add(type,module,s,b);add(totals,module,s,b);
    modules.set(module,(modules.get(module)??0)+1);
  }
  if(totals.open!==open.total||totals.stale!==stale.total||
     totals.blocked!==blocked.total||
     Object.values(totals.modules).reduce((a,b)=>a+b,0)!==totals.open){
    throw Error("jira_assignee_matrix_total_reconciliation_failed");
  }
  const assignees:Array<AssigneeRow>=[...owners].map(([key,entry])=>({
    key,name:key==="__unassigned__"?"Unassigned":key,...entry.counts,
    types:[...entry.types].map(([type,counts])=>({type,...counts}))
      .sort((a,b)=>b.open-a.open||a.type.localeCompare(b.type)),
  })).sort((a,b)=>b.open-a.open||a.name.localeCompare(b.name));
  if(assignees.reduce((sum,row)=>sum+row.open,0)!==totals.open)throw Error("jira_assignee_matrix_assignee_mismatch");
  const rankedModules=[...modules].map(([key,count])=>({
    key,name:key===UNTAGGED_MODULE?"Untagged":key,count,
  })).sort((a,b)=>b.count-a.count||a.name.localeCompare(b.name));
  return{
    snapshot_id:snapshot,synced_at:dashboard.synced_at,filters,
    totals:{...totals,assignees:assignees.filter(x=>x.key!=="__unassigned__").length,
      untagged:totals.modules[UNTAGGED_MODULE]??0},
    assignees,modules:rankedModules,
    options:{sprints:dashboard.options.sprints.map(s=>({
      sprint_id:s.sprint_id,sprint_name:s.sprint_name,state:s.state,
    })),modules:dashboard.options.modules,
      sub_modules:dashboard.options.sub_modules,
      severities:dashboard.options.severities},
  };
}
