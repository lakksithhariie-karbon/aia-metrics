"use client";

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import type {
  DeliveryDashboard, DeliveryEvidence, DeliveryFilters,
  FlowStageRow, SprintRow, ThroughputRow,
} from "../../lib/delivery/types";

/** Engineering & Delivery on the exact shared Product Metrics outer grid.
 * All 15 headline cards and 6 analytical panels are backed by audited Jira
 * readers. No screenshot fixtures, local metrics, or invented history.
 */
type Metric = {
  id: string;
  label: string;
  value: string;
  unit?: string;
  caption: string;
  evidence: string;
  definition: string;
  source: string;
  drillKey?: string;
  sprintId?: number | null;
  highlighted?: boolean;
  attention?: boolean;
};
type DrillTarget = { key: string; label: string; sprintId: number | null };
const nf = new Intl.NumberFormat("en-IN",{maximumFractionDigits:0});
const num = (v: number | null | undefined): string =>
  typeof v==="number" && Number.isFinite(v) ? nf.format(v) : "—";
const decimal = (v: number | null | undefined, digits=1): string =>
  typeof v==="number" && Number.isFinite(v) ? v.toFixed(digits) : "—";
const pct = (v: number | null | undefined, digits=1): string =>
  typeof v==="number" && Number.isFinite(v) ? decimal(v,digits)+"%" : "—";
const hrs = (v: number | null | undefined): string =>
  typeof v!=="number" || !Number.isFinite(v) ? "—" :
  v >= 48 ? decimal(v/24,1)+"d" : decimal(v,1)+"h";
const date = (iso: string): string => {
  const d=new Date(iso);
  return Number.isFinite(d.getTime()) ?
    new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Kolkata",day:"2-digit",month:"short",year:"2-digit"}).format(d) : "—";
};
const freshness = (iso: string): string => {
  const d=new Date(iso);
  return Number.isFinite(d.getTime()) ?
    new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Kolkata",day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit",hourCycle:"h23"}).format(d)+" IST" : "Unavailable";
};
const shortSprint = (value: string): string => value.replace(/^SPEND\s+/,"");
const empty = (s: string | null | undefined): string => s?.trim() || "Untagged";

function SectionHead({title,question}:{title:string;question:string}){
  return <div className="metrics-section-kicker ed-section-heading">
    <span>{title}</span><span className="metrics-section-description">{question}</span>
  </div>;
}
function Surface({title,subtitle,children,half=false}:{
  title:string;subtitle:string;children:ReactNode;half?:boolean;
}){
  return <article className={"report-card ed-report"+(half?" ed-report-half":"")}>
    <div className="report-header ed-report-heading">
      <div><h2>{title}</h2><p className="report-subtitle">{subtitle}</p></div>
    </div>{children}
  </article>;
}
function InfoIcon({label,onClick}:{label:string;onClick:()=>void}){
  return <button className="ed-info-button" type="button" aria-label={"How "+label+" is calculated"} title="Metric definition" onClick={onClick}>
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="1.8"/>
      <path d="M12 11v5m0-8v.1" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
    </svg>
  </button>;
}
function MetricTile({metric,onInfo,onDrill}:{
  metric:Metric;onInfo:(m:Metric)=>void;onDrill:(target:DrillTarget)=>void;
}){
  return <article className={"metric-card ed-metric"+(metric.highlighted?" ed-metric-featured":"")}>
    <div className="ed-metric-label">{metric.label}</div>
    <InfoIcon label={metric.label} onClick={()=>onInfo(metric)}/>
    <div className="ed-metric-readout">
      <strong>{metric.value}</strong>
      {metric.unit?<span>{metric.unit}</span>:null}
    </div>
    <p className={"ed-metric-caption"+(metric.attention?" ed-metric-caption-attention":"")}>{metric.caption}</p>
    <div className="ed-metric-bottom">
      {metric.drillKey?(
        <button type="button" className="ed-drill-link" onClick={()=>onDrill({
          key:metric.drillKey!,label:metric.label,sprintId:metric.sprintId??null,
        })}>{metric.evidence}<span aria-hidden="true">↗</span></button>
      ):<span>{metric.evidence}</span>}
    </div>
  </article>;
}
function FilterBar({data,filters}:{
  data:DeliveryDashboard;filters:DeliveryFilters;
}){
  return <form key={JSON.stringify(filters)} className="ed-filters" method="GET" action="/delivery" aria-label="Jira delivery filters">
    <label className="ed-filter-label"><span>Sprint</span>
      <select name="sprint" defaultValue={filters.sprint??""}>
        <option value="">All sprints</option>
        {data.options.sprints.map(s=><option key={s.sprint_id} value={s.sprint_id}>
          {shortSprint(s.sprint_name)} · {s.state}
        </option>)}
      </select>
    </label>
    <label className="ed-filter-label"><span>Module</span>
      <select name="module" defaultValue={filters.module??""}>
        <option value="">All modules</option>
        <option value="__untagged__">Untagged</option>
        {data.options.modules.map(x=><option key={x} value={x}>{x}</option>)}
      </select>
    </label>
    <label className="ed-filter-label"><span>Sub-module</span>
      <select name="sub_module" defaultValue={filters.sub_module??""}>
        <option value="">All sub-modules</option>
        <option value="__untagged__">Untagged</option>
        {data.options.sub_modules.map(x=><option key={x} value={x}>{x}</option>)}
      </select>
    </label>
    <label className="ed-filter-label"><span>Severity</span>
      <select name="severity" defaultValue={filters.severity??""}>
        <option value="">All severities</option>
        <option value="Untagged">Untagged</option>
        {data.options.severities.map(x=><option key={x} value={x}>{x}</option>)}
      </select>
    </label>
    <label className="ed-filter-label"><span>Assignee</span>
      <select name="assignee" defaultValue={filters.assignee??""}>
        <option value="">All assignees</option>
        {data.options.assignees.map(x=><option key={x} value={x}>{x}</option>)}
      </select>
    </label>
    <button type="submit" className="ed-apply">Apply</button>
    <a href="/delivery" className="ed-clear">Clear</a>
  </form>;
}
function WorkInFlight({data,open}:{
  data:DeliveryDashboard;open:(target:DrillTarget)=>void;
}){
  const counts=data.flow.wip_by_status;
  return <Surface title="Work in flight" subtitle={num(data.flow.flow_counts.open_total)+" open issues by current Jira status"}>
    <div className="ed-table-shell ed-table-grow" role="region" tabIndex={0} aria-label="Current open issues by status">
      <table className="ed-report-table ed-status-table">
        <thead><tr><th>Status</th><th>Open issues</th><th>Share of queue</th><th>Signal</th></tr></thead>
        <tbody>{counts.map(row=>{
          const label=row.status_name==="Blocked/Onhold"?"Blocked / On hold":row.status_name;
          const alert=row.status_name==="Blocked/Onhold";
          return <tr key={row.status_name} className={alert?"ed-row-attention":""}>
            <th scope="row"><button className="ed-cell-drill" type="button" onClick={()=>open({
              key:"status:"+row.status_name,label:label,sprintId:data.selected_sprint_id,
            })}>{label} <span aria-hidden="true">↗</span></button></th>
            <td>{num(row.issue_count)}</td>
            <td><span className="ed-share">
              <span className="ed-share-track" aria-hidden="true">
                <span style={{width:Math.max(0,Math.min(100,row.pct))+"%"}}/>
              </span><span>{pct(row.pct)}</span>
            </span></td>
            <td className={alert?"ed-signal-alert":""}>
              {alert?"Needs action":row.status_name==="To Do"?"Queue":row.status_name==="Reopen"?"Rework":"In progress"}
            </td>
          </tr>;
        })}</tbody>
      </table>
    </div>
    <p className="ed-table-meta">Every row opens its matching Jira issue population. Statuses total {num(data.flow.flow_counts.open_total)}.</p>
  </Surface>;
}
function PlannedVsDone({data}: {data:DeliveryDashboard}){
  const sprints=data.core.sprint_discipline;
  const throughput=new Map(data.core.sprint_throughput.map(x=>[x.sprint_id,x]));
  const rows=[
    {label:"Committed work finished",get:(s:SprintRow)=>pct(s.commitment_completion_pct),key:true},
    {label:"Committed / delivered",get:(s:SprintRow)=>num(s.committed_done)+" / "+num(s.committed)},
    {label:"Carried to next",get:(s:SprintRow)=>num(s.carried_to_next)},
    {label:"Scope now",get:(s:SprintRow)=>num(s.scope_now)},
    {label:"Completed now",get:(s:SprintRow)=>num(s.done_now)},
    {label:"Throughput",get:(s:SprintRow)=>num(throughput.get(s.sprint_id)?.throughput)},
    {label:"Late-added completions",get:(s:SprintRow)=>num(throughput.get(s.sprint_id)?.first_done_after_start)},
    {label:"Window",get:(s:SprintRow)=>date(s.start_date)+" – "+date(s.end_date)},
  ];
  return <Surface title="Planned versus done" subtitle="Sprint commitment, completed issues and throughput · Current issue state">
    <div className="ed-table-shell" role="region" tabIndex={0} aria-label="Sprint planning and throughput comparison">
      <table className="ed-report-table ed-compare">
        <thead><tr><th>Measure</th>{sprints.map(s=>
          <th key={s.sprint_id}>{shortSprint(s.sprint_name)}<small>{s.state}</small></th>)}</tr></thead>
        <tbody>{rows.map(row=><tr key={row.label} className={row.key?"ed-row-key":""}>
          <th scope="row">{row.label}</th>
          {sprints.map(s=><td key={s.sprint_id}>{row.get(s)}</td>)}
        </tr>)}</tbody>
      </table>
    </div>
  </Surface>;
}
function IssueTypes({data,open}:{data:DeliveryDashboard;open:(target:DrillTarget)=>void}){
  const sprints=data.core.sprint_discipline;
  const types=Array.from(new Set(data.issue_types.map(x=>x.issue_type))).sort((a,b)=>a.localeCompare(b));
  const lookup=new Map(data.issue_types.map(x=>[x.sprint_id+"|"+x.issue_type,x.count]));
  return <Surface title="Issue types by sprint" subtitle="Direct Jira sprint issues · Subtasks excluded · Same population as sprint scope">
    <div className="ed-table-shell" role="region" tabIndex={0} aria-label="Issue type distribution for compared sprints">
      <table className="ed-report-table ed-issue-types" style={{minWidth:Math.max(660,(types.length+1)*104)}}>
        <thead><tr><th>Sprint</th>{types.map(t=><th key={t}>{t}</th>)}</tr></thead>
        <tbody>{sprints.map(s=><tr key={s.sprint_id}>
          <th scope="row">{shortSprint(s.sprint_name)}</th>
          {types.map(t=>{
            const count=lookup.get(s.sprint_id+"|"+t)??0;
            return <td key={t}>{count>0?(
              <button className="ed-cell-drill" type="button" onClick={()=>open({
                key:"type:"+t,label:shortSprint(s.sprint_name)+" · "+t,sprintId:s.sprint_id,
              })}>{num(count)} <span aria-hidden="true">↗</span></button>
            ):<span className="ed-zero">0</span>}</td>;
          })}
        </tr>)}</tbody>
      </table>
    </div>
  </Surface>;
}
function FlowHealth({data,sprint}:{data:DeliveryDashboard;sprint:SprintRow}){
  const stages=data.flow.stage_summary.filter(s=>s.sprint_id===sprint.sprint_id)
    .sort((a,b)=>(b.median_hours??0)-(a.median_hours??0));
  const cycle = data.selected_sprint_id != null ?
    data.core.cycle_time_by_sprint.find(x=>x.sprint_id===sprint.sprint_id) :
    data.core.cycle_time_org;
  const maxHours=Math.max(1,...stages.map(s=>s.median_hours??0));
  return <Surface title="Flow health" subtitle={"Median stage dwell · "+shortSprint(sprint.sprint_name)}>
    <div className="ed-flow-summary"><div>
      <span>Engineering cycle time</span>
      <div className="ed-flow-value">{decimal(cycle?.median_days,2)}<span>d</span></div>
      <p>Median first In Progress → Done · {num(cycle?.n)} measured issues</p>
    </div><div className="ed-flow-measured">{stages.length} instrumented stages</div></div>
    <div className="ed-table-shell" role="region" tabIndex={0} aria-label="Stage dwell time in the selected sprint">
      <table className="ed-report-table ed-flow-table">
        <thead><tr><th>Stage</th><th>Median dwell</th><th>Duration / stays</th></tr></thead>
        <tbody>{stages.map(s=><tr key={s.stage}>
          <th scope="row">{s.stage.toLowerCase()==="uat"?"UAT":s.stage}</th>
          <td><span className="ed-flow-track" aria-hidden="true"><span
            className={s.stage==="Blocked/Onhold"?"ed-flow-danger":""}
            style={{width:Math.max(1,(s.median_hours??0)/maxHours*100)+"%"}}/></span></td>
          <td>{hrs(s.median_hours)} <small>· {num(s.issues_in_stage)}</small></td>
        </tr>)}</tbody>
      </table>
    </div>
  </Surface>;
}
function BacklogTrend({data}:{data:DeliveryDashboard}){
  const series=data.flow.backlog_trend.filter(x=>Number.isFinite(x.open_eod)).slice(-20);
  const width=840,height=175,left=38,right=15,top=18,bottom=29;
  const values=series.map(s=>s.open_eod),lo=Math.min(...values,0),hi=Math.max(...values,1);
  const vertical=Math.max(1,hi-lo);
  const x=(i:number)=>left+(i/Math.max(1,series.length-1))*(width-left-right);
  const y=(v:number)=>top+(1-(v-lo)/vertical)*(height-top-bottom);
  const path=series.map((s,i)=>(i===0?"M":"L")+x(i).toFixed(1)+","+y(s.open_eod).toFixed(1)).join(" ");
  return <Surface title="Backlog trajectory" subtitle="Weekly end-of-week open issues · Published Jira reporting series" half>
    <div className="ed-trend-wrap">
      {series.length>1?<svg viewBox={"0 0 "+width+" "+height} role="img" aria-label={"Backlog starts at "+values[0]+" and ends at "+values[values.length-1]+" open issues"}>
        {[0,.5,1].map(f=><g key={f}><line x1={left} y1={y(lo+(hi-lo)*f)} x2={width-right} y2={y(lo+(hi-lo)*f)}
            stroke="#e4eaf2" strokeWidth="1"/><text x={left-7} y={y(lo+(hi-lo)*f)+4} textAnchor="end" fontSize="12" fill="#8b9aae">{num(Math.round(lo+(hi-lo)*f))}</text></g>)}
        <path d={path} fill="none" stroke="#416de8" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round"/>
        {series.map((s,i)=><circle key={s.week_start} cx={x(i)} cy={y(s.open_eod)} r="3" fill="#416de8">
          <title>{date(s.week_start)}: {num(s.open_eod)} open issues</title></circle>)}
        <text x={left} y={height-5} fill="#8b9aae" fontSize="12">{date(series[0].week_start)}</text>
        <text x={width-right} y={height-5} fill="#8b9aae" fontSize="12" textAnchor="end">{date(series[series.length-1].week_start)}</text>
      </svg>:<p className="ed-table-meta">Not enough reporting weeks.</p>}
      <p className="ed-trend-meta">{series.length} weekly points · Most recent week {series.length?num(series[series.length-1].open_eod):"—"} open</p>
    </div>
  </Surface>;
}
function BugAging({data}:{data:DeliveryDashboard}){
  const rows=data.flow.bug_health.age_histogram;
  return <Surface title="Open bug aging" subtitle="Age since Jira issue creation · Completes to the open bug total" half>
    <div className="ed-aging">
      {rows.map(row=><div className="ed-aging-row" key={row.bucket}>
        <span>{row.bucket}</span><span className="ed-aging-track"><i style={{width:Math.max(1,row.pct)+"%"}}/></span>
        <strong>{num(row.count)}</strong><small>{pct(row.pct)}</small>
      </div>)}
      <p>{num(data.flow.bug_health.open_bugs)} open bugs · Median age {decimal(data.flow.bug_health.median_age_days)} days</p>
    </div>
  </Surface>;
}

function DefinitionDialog({metric,onClose}:{metric:Metric;onClose:()=>void}){
  useEffect(()=>{
    const key=(event:KeyboardEvent)=>{if(event.key==="Escape")onClose();};
    document.addEventListener("keydown",key);
    return ()=>document.removeEventListener("keydown",key);
  },[onClose]);
  return <div className="ed-overlay" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)onClose();}}>
    <section className="ed-definition-dialog" role="dialog" aria-modal="true" aria-labelledby="ed-definition-title">
      <header><div><span>METRIC DEFINITION</span><h2 id="ed-definition-title">{metric.label}</h2></div>
        <button type="button" onClick={onClose} aria-label="Close definition">×</button></header>
      <div className="ed-definition-body">
        <h3>How it's calculated</h3><p>{metric.definition}</p>
        <h3>Data source</h3><p>{metric.source}</p>
        <h3>Published value</h3><p>{metric.value}{metric.unit?" "+metric.unit:""}</p>
      </div>
    </section>
  </div>;
}
function EvidenceDialog({target,data,filters,onClose}:{target:DrillTarget;data:DeliveryDashboard;filters:DeliveryFilters;onClose:()=>void}){
  const [offset,setOffset]=useState(0);
  const [result,setResult]=useState<DeliveryEvidence|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState(false);
  const firstButton=useRef<HTMLButtonElement>(null);
  useEffect(()=>{
    firstButton.current?.focus({preventScroll:true});
    const onKey=(e:KeyboardEvent)=>{if(e.key==="Escape")onClose();};
    document.addEventListener("keydown",onKey);
    return ()=>document.removeEventListener("keydown",onKey);
  },[onClose]);
  useEffect(()=>{
    const controller=new AbortController();
    fetch("/api/delivery/evidence",{
      method:"POST",cache:"no-store",signal:controller.signal,
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({
        key:target.key,snapshot_id:data.snapshot_id,offset,
        filters:{...filters,sprint:target.sprintId},
      }),
    }).then(async response=>{
      if(!response.ok)throw new Error("evidence_request_failed");
      return (await response.json()) as DeliveryEvidence;
    }).then(value=>{
      if(value.contract!=="jira_delivery_evidence_v1"||
         value.snapshot_id!==data.snapshot_id||value.key!==target.key) {
        throw new Error("evidence_contract_mismatch");
      }
      setResult(value);setError(false);setLoading(false);
    }).catch(err=>{
      if(controller.signal.aborted)return;
      console.error("delivery_evidence_read",err instanceof Error?err.message:"unknown");
      setResult(null);setError(true);setLoading(false);
    });
    return ()=>controller.abort();
  },[target.key,target.sprintId,data.snapshot_id,filters.sprint,filters.module,filters.sub_module,filters.severity,filters.assignee,offset]);
  const next=()=>{setLoading(true);setResult(null);setOffset(x=>x+40);};
  const previous=()=>{setLoading(true);setResult(null);setOffset(x=>Math.max(0,x-40));};
  return <div className="ed-overlay" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)onClose();}}>
    <section className="ed-evidence-dialog" role="dialog" aria-modal="true" aria-labelledby="ed-evidence-title">
      <header><div><span>VERIFIED JIRA ISSUE EVIDENCE · SYNC {data.snapshot_id}</span>
        <h2 id="ed-evidence-title">{target.label}</h2></div>
        <button ref={firstButton} type="button" aria-label="Close issue evidence" onClick={onClose}>×</button></header>
      <div className="ed-evidence-summary">
        {loading?"Loading issue evidence…":error?"Evidence temporarily unavailable":
        <>{num(result?.total)} matching issues{result && result.source_count!==result.total?
          " · "+num(result.source_count)+" reported metric events / cycles":""}
          {" · "}Rows {num(result&&result.total?offset+1:0)}–{num(Math.min(offset+40,result?.total??0))}
        </>}
      </div>
      <div className="ed-evidence-table-shell">
        {error?<p role="alert" className="ed-error">Couldn’t verify the selected issue population. No unverified rows are shown.</p>:
        loading?<p className="ed-table-meta">Querying the published Jira snapshot…</p>:
        !result?.rows.length?<p className="ed-table-meta">No matching issues in this scope.</p>:
        <table className="ed-report-table ed-evidence-table">
          <thead><tr><th>Jira issue</th><th>Summary</th><th>Status</th><th>Priority</th><th>Module</th><th>Assignee</th></tr></thead>
          <tbody>{result.rows.map((row,index)=><tr key={row.issue_key+"-"+index}>
            <th scope="row"><a href={"https://karbonworks.atlassian.net/browse/"+encodeURIComponent(row.issue_key)}
                target="_blank" rel="noopener noreferrer">{row.issue_key} ↗</a></th>
            <td title={row.summary??""}>{row.summary||"Untitled Jira issue"}</td>
            <td>{empty(row.status)}</td><td>{empty(row.priority)}</td>
            <td>{empty(row.module)}</td><td>{empty(row.assignee)}</td>
          </tr>)}</tbody>
        </table>}
      </div>
      <footer className="ed-evidence-footer">
        <span>Jira issue keys open in Atlassian · No unverified data</span>
        <div><button disabled={loading||offset===0} onClick={previous} type="button">Previous</button>
        <button disabled={loading||!result||offset+40>=result.total} onClick={next} type="button">Next 40</button></div>
      </footer>
    </section>
  </div>;
}

export default function EngineeringDeliveryShell({data,filters,error}:{
  data:DeliveryDashboard|null;filters:DeliveryFilters;error:string|null;
}){
  const [info,setInfo]=useState<Metric|null>(null);
  const [drill,setDrill]=useState<DrillTarget|null>(null);
  if(!data) {
    return <main className="rd-page ed-page">
      <div className="rd-page-head ed-page-head"><div className="ed-page-copy">
        <h1>Engineering &amp; Delivery</h1>
        <p>Jira sprint delivery, issue flow and quality reporting</p>
      </div></div>
      <section className="metrics-grid-section ed-section">
        <div className="ed-error ed-global-error" role="alert">
          <strong>Verified data unavailable</strong>
          <p>{error??"The Jira reporting snapshot is unavailable."}</p>
          <a href="/delivery">Retry</a>
        </div>
      </section>
    </main>;
  }
  const c=data.core.metric_cohorts;
  const first=data.core.sprint_discipline.find(s=>s.state==="active")
    ??data.core.sprint_discipline[0];
  if(!first){
    return <main className="rd-page ed-page"><div className="ed-error ed-global-error">
      No audited sprint is available for the current filter.</div></main>;
  }
  const source="Jira SPEND · published sync "+data.snapshot_id;
  const cohort=(key:string)=>c[key]?.n??null;
  const metricAction=(key:string)=>c[key]?.n!=null?key:undefined;
  const throughput=data.core.sprint_throughput.find(x=>x.sprint_id===first.sprint_id);
  const gap=first.committed-first.committed_done;
  const q=data.quality.metric_updates;
  const codeReview=data.flow.metric_updates.code_review;
  const isHistorical=first.state!=="active";
  const sprintMetrics:Metric[]=[
    {id:"commitment",label:(first.state==="active"?"Active":"Selected")+" sprint · "+first.sprint_name,
      value:pct(first.commitment_completion_pct),caption:num(first.committed_done)+" of "+num(first.committed)+" committed issues completed",
      evidence:"View "+num(cohort("commit_s45"))+" delivered issues",
      definition:"Completed committed issues divided by all originally committed direct sprint issues. Commitment uses the sprint-start plus two-day cutoff; removed-before-cutoff items are excluded.",
      source:"jira.v_sprint_discipline · verified sprint cohort",highlighted:true,
      drillKey:metricAction("commit_s45"),sprintId:filters.sprint,attention:true},
    {id:"commitment_gap",label:"Committed work not delivered",
      value:num(gap),unit:"issues",caption:"Committed by cutoff · currently not Done",
      evidence:"View "+num(gap)+" incomplete committed issues",
      definition:"Original committed direct sprint issues minus those currently Done. The issue population matches the sprint discipline removal cutoff.",
      source:"jira.v_sprint_discipline + filtered sprint issue evidence",drillKey:"commitment_gap",sprintId:filters.sprint},
    {id:"mid_sprint",label:"Mid-sprint additions",value:num(first.added_mid_sprint),unit:"issues",
      caption:pct(first.mid_sprint_add_pct)+" of current sprint scope",evidence:"View "+num(cohort("adds_s45"))+" added issues",
      definition:"Direct sprint issues created after the sprint-start plus two-day commitment cutoff, within the published sprint population.",
      source:"jira.v_sprint_discipline / adds_s45 published cohort",drillKey:metricAction("adds_s45"),sprintId:filters.sprint},
    {id:"throughput",label:"Throughput",value:num(throughput?.throughput),unit:"completed",
      caption:num(throughput?.first_done_after_start)+" first completed after sprint start",
      evidence:"View "+num(cohort("throughput_s45"))+" completed issue records",
      definition:"Distinct Jira issues first completed during the sprint reporting window. This is a throughput measure, not the count currently Done in sprint scope.",
      source:"jira.v_sprint_throughput / throughput_s45 published cohort",
      drillKey:metricAction("throughput_s45"),sprintId:filters.sprint},
  ];
  const fc=data.flow.flow_counts;
  const attention:Metric[]=[
    {id:"stale",label:"Stale work",value:num(fc.stale_all),unit:"issues",
      caption:"Open issues not updated for 7+ days",evidence:"View "+num(cohort("stale_7d"))+" stale issues",
      definition:"Open issues whose last Jira update is older than seven days. Deleted Jira issues are excluded.",
      source:"jira.v_issue_flow_state / stale_7d cohort",drillKey:metricAction("stale_7d")},
    {id:"stale_blocked",label:"Stale and blocked",value:num(fc.stale_blocked),unit:"issues",
      caption:"Blocked status and stale for 7+ days",
      evidence:"View "+num(cohort("stale_blocked"))+" issues",
      definition:"Open issues with status Blocked/Onhold and no Jira update in the past seven days.",
      source:"jira.v_flow_counts / stale_blocked cohort",drillKey:metricAction("stale_blocked")},
    {id:"l1",label:"Open L1 bugs",value:num(cohort("open_l1_s45")),unit:"bugs",
      caption:"Open issues classified L1 · untagged retained elsewhere",
      evidence:"View "+num(cohort("open_l1_s45"))+" L1 bugs",
      definition:"Not-Done Jira bug issues explicitly tagged with severity L1. Issues missing severity remain in total open bugs, not this segment.",
      source:"jira.v_metric_cohorts_active_v1 / open_l1_s45",drillKey:metricAction("open_l1_s45")},
    {id:"qa_queue",label:"QA queue",value:num(fc.open_total>=0?cohort("qa_queue"):null),unit:"open",
      caption:"Open issues awaiting UAT, testing or staging exit",
      evidence:"View "+num(cohort("qa_queue"))+" issue records",
      definition:"Open issues currently in UAT, Testing or Staging, matching the audited QA queue population.",
      source:"jira.v_qa_queue / qa_queue cohort",drillKey:metricAction("qa_queue")},
    {id:"blocked",label:"Blocked",value:num(fc.blocked_all),unit:"issues",
      caption:pct(fc.open_total?fc.blocked_all/fc.open_total*100:null)+" of current open work",
      evidence:"View "+num(cohort("blocked"))+" blocked issues",
      definition:"Open Jira issues currently in Blocked/Onhold. Denominator is all currently open, non-deleted issues.",
      source:"jira.v_flow_counts / blocked cohort",drillKey:metricAction("blocked"),attention:true},
  ];
  const qReopen=q.reopen_latest, qReject=q.qa_rejection,qResolution=q.bug_resolution,qTurn=q.qa_turnaround;
  const bugAging=data.flow.bug_health;
  const quality:Metric[]=[
    {id:"bugs",label:"Open bug backlog",value:num(bugAging.open_bugs),unit:"open bugs",
      caption:"Median age "+decimal(bugAging.median_age_days)+"d",
      evidence:"View "+num(cohort("open_bugs"))+" open bugs",
      definition:"Jira issues of type Bug not in Done status, excluding Jira-deleted issues. Median age is measured from creation.",
      source:"jira.v_bug_health / open_bugs cohort",drillKey:metricAction("open_bugs"),highlighted:true},
    {id:"reopen",label:"Reopen rate",value:pct(qReopen?.value),caption:num(qReopen?.n)+" of "+num(qReopen?.denominator)+" closes · latest completed month",
      evidence:"View "+num(cohort("reopen_latest"))+" reopened issues",
      definition:"Reopened issues relative to the published closed-issue denominator for the latest measured month. Historical status changes are used.",
      source:"jira.get_filtered_dashboard_quality_submodule / reopen_latest cohort",drillKey:metricAction("reopen_latest")},
    {id:"qa_reject",label:"QA rejection",value:pct(qReject?.value,2),caption:num(qReject?.n)+" rejected cycles of "+num(qReject?.denominator)+" decisions",
      evidence:"View affected Jira issue records",
      definition:"Rejected UAT cycles divided by accepted plus rejected UAT decisions. The rate counts decisions; the issue drill lists distinct affected issue records.",
      source:"jira.v_qa_rejection_org / qa_rejection cohort",drillKey:metricAction("qa_rejection")},
    {id:"bug_resolution",label:"Bug resolution",value:decimal(qResolution?.value,2)+"d",
      caption:"Median created → resolved · "+num(qResolution?.n)+" bugs",
      evidence:"View resolved bug evidence",
      definition:"Median elapsed days from Jira bug creation to its published resolved timestamp, using the filtered resolved-bug population.",
      source:"jira.v_resolution_medians / bug_resolution cohort",drillKey:metricAction("bug_resolution")},
    {id:"qa_turn",label:"QA turnaround",value:decimal(qTurn?.value!=null?qTurn.value/24:null,1)+"d",
      caption:"Median UAT stay · "+num(qTurn?.n)+" measured",
      evidence:"View UAT decision evidence",
      definition:"Median hours from UAT entry to a recorded exit decision, displayed in days (hours divided by 24). Incomplete/open windows are excluded.",
      source:"jira.v_resolution_medians / qa_turnaround cohort",drillKey:metricAction("qa_turnaround")},
    {id:"code_review",label:"Code review",value:hrs(codeReview?.value),caption:"Median stage dwell · "+shortSprint(first.sprint_name),
      evidence:"View "+num(cohort("code_review"))+" review stays",
      definition:"Median measured Code Review status dwell in the selected sprint's stage records. It is not developer productivity or time spent typing code.",
      source:"jira.v_sprint_stage_summary / code_review cohort",drillKey:metricAction("code_review"),sprintId:filters.sprint},
  ];
  const sourceAgeMs=Date.now()-Date.parse(data.synced_at);
  const isStale=sourceAgeMs>36*3600*1000 || sourceAgeMs<0;
  const apply=(m:Metric)=>setInfo(m);
  const drillTo=(d:DrillTarget)=>setDrill(d);
  return <>
    <main className="rd-page ed-page">
      <div className="rd-page-head ed-page-head">
        <div className="ed-page-copy">
          <div className="ed-titleline"><h1>Engineering &amp; Delivery</h1>
            <span className={"ed-reference-badge ed-live-badge"+(isStale?" ed-stale-badge":"")}>
              {isStale?"Sync delayed":"Verified Jira"} · {freshness(data.synced_at)}
            </span></div>
          <p>Sprint delivery, attention, flow and quality · Published sync {data.snapshot_id}</p>
        </div>
        <FilterBar data={data} filters={filters}/>
      </div>
      {isHistorical?<p className="ed-historical-warning" role="status">
        Historical sprint selected. Completion reflects the <strong>current status</strong> of its issues,
        not a reconstructed sprint-close snapshot.
      </p>:null}
      {isStale?<p className="ed-historical-warning" role="status">
        The latest verified Jira sync is older than 36 hours. Metrics remain labeled with their source cutoff.
      </p>:null}

      <section className="metrics-grid-section ed-section" aria-label="Sprint delivery">
        <SectionHead title="Sprint delivery" question="Did we finish the work we planned?"/>
        <div className="ed-sprint-kpis">{sprintMetrics.map(m=>
          <MetricTile key={m.id} metric={m} onInfo={apply} onDrill={drillTo}/>)}</div>
      </section>
      <section className="metrics-grid-section ed-section" aria-label="Attention">
        <SectionHead title="Attention" question="Work requiring action now"/>
        <div className="ed-five-kpis">{attention.map(m=>
          <MetricTile key={m.id} metric={m} onInfo={apply} onDrill={drillTo}/>)}</div>
        <div className="ed-collection"><WorkInFlight data={data} open={drillTo}/></div>
      </section>
      <section className="metrics-grid-section ed-section" aria-label="Delivery">
        <SectionHead title="Delivery" question="Commitment, throughput and issue mix by sprint"/>
        <div className="ed-collection">
          <PlannedVsDone data={data}/>
          <IssueTypes data={data} open={drillTo}/>
        </div>
      </section>
      <section className="metrics-grid-section ed-section" aria-label="Flow">
        <SectionHead title="Flow" question="Where does work wait, and how long does it take?"/>
        <div className="ed-collection"><FlowHealth data={data} sprint={first}/></div>
      </section>
      <section className="metrics-grid-section ed-section" aria-label="Quality">
        <SectionHead title="Quality" question="Defect stock, rejection, recovery and cycle time"/>
        <div className="ed-five-kpis">{quality.map(m=>
          <MetricTile key={m.id} metric={m} onInfo={apply} onDrill={drillTo}/>)}</div>
        <div className="ed-collection">
          <BugAging data={data}/><BacklogTrend data={data}/>
        </div>
      </section>
      <footer className="ed-preview-note">
        <strong>Verified source:</strong> Jira SPEND · Supabase snapshot {data.snapshot_id} ·
        Last verified ingestion {freshness(data.synced_at)} ·
        Filtered card values and issue evidence use the same reporting scope.
        Historical sprint completion is based on current issue status.
      </footer>
    </main>
    {info?<DefinitionDialog metric={info} onClose={()=>setInfo(null)}/>:null}
    {drill?<EvidenceDialog target={drill} data={data} filters={filters} onClose={()=>setDrill(null)}/>:null}
  </>;
}
