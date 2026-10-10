"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import CompactMenuSelect from "../ui/compact-menu-select";
import DeliveryEvidenceModal from "./delivery-evidence-modal";
import type { ReactNode } from "react";
import type {
  DeliveryDashboard, DeliveryFilters,
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
  period: string;
  definition: string;
  source: string;
  drillKey?: string;
  sprintId?: number | null;
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
  const openCard=()=>{
    if(metric.drillKey){
      onDrill({key:metric.drillKey,label:metric.label,sprintId:metric.sprintId??null});
    } else {
      onInfo(metric);
    }
  };
  // Match Product Overview: full-card native button, separate help control.
  // Neither nested buttons nor extra CTA links are needed.
  return <div className="ed-metric-wrap">
    <button type="button"
      className="metric-card ed-metric"
      onClick={openCard}
      aria-haspopup="dialog"
      aria-label={metric.label+": "+metric.value+(metric.drillKey?". View matching Jira issues.":". View metric definition.")}>
      <span className="po-kpi-divider" aria-hidden="true"/>
      <span className="metric-label">{metric.label}</span>
      <span className="metric-period">{metric.period}</span>
      <span className="metric-value">{metric.value}
        {metric.unit?<span className="unit">{metric.unit}</span>:null}
      </span>
      <span className={"metric-note"+(metric.attention?" ed-metric-note-attention":"")}>{metric.caption}</span>
    </button>
    <InfoIcon label={metric.label} onClick={()=>onInfo(metric)}/>
  </div>;
}
function FilterBar({data,filters}:{
  data:DeliveryDashboard;filters:DeliveryFilters;
}){
  const router=useRouter();
  const applyFilter=(name:keyof DeliveryFilters,value:string)=>{
    // Keep the existing URL-filter contract. A menu selection applies
    // immediately and retains all other filter dimensions.
    const query=new URLSearchParams(window.location.search);
    if(value)query.set(name,value);
    else query.delete(name);
    const search=query.toString();
    router.replace("/delivery"+(search?"?"+search:""),{scroll:false});
  };
  // Reuse the exact Product/Retention CompactMenuSelect control. Stable option
  // arrays prevent keyboard focus from jumping when React rerenders.
  const sprintOptions=useMemo(()=>[
    {value:"",label:"All sprints"},
    ...data.options.sprints.map(s=>({
      value:String(s.sprint_id),label:shortSprint(s.sprint_name)+" · "+s.state,
    })),
  ],[data.options.sprints]);
  const moduleOptions=useMemo(()=>[
    {value:"",label:"All modules"},{value:"__untagged__",label:"Untagged"},
    ...data.options.modules.map(x=>({value:x,label:x})),
  ],[data.options.modules]);
  const submoduleOptions=useMemo(()=>[
    {value:"",label:"All sub-modules"},{value:"__untagged__",label:"Untagged"},
    ...data.options.sub_modules.map(x=>({value:x,label:x})),
  ],[data.options.sub_modules]);
  const severityOptions=useMemo(()=>[
    {value:"",label:"All severities"},{value:"Untagged",label:"Untagged"},
    ...data.options.severities.map(x=>({value:x,label:x})),
  ],[data.options.severities]);
  const assigneeOptions=useMemo(()=>[
    {value:"",label:"All assignees"},
    ...data.options.assignees.map(x=>({value:x,label:x})),
  ],[data.options.assignees]);
  return <div className="ed-filters" role="group" aria-label="Jira delivery filters">
    <div className="ed-filter-label"><span>Sprint</span>
      <CompactMenuSelect value={filters.sprint===null?"":String(filters.sprint)}
        options={sprintOptions} onChange={value=>applyFilter("sprint",value)}
        ariaLabel="Filter by sprint" className="ed-delivery-filter-select"/>
    </div>
    <div className="ed-filter-label"><span>Module</span>
      <CompactMenuSelect value={filters.module??""}
        options={moduleOptions} onChange={value=>applyFilter("module",value)}
        ariaLabel="Filter by module" className="ed-delivery-filter-select"/>
    </div>
    <div className="ed-filter-label"><span>Sub-module</span>
      <CompactMenuSelect value={filters.sub_module??""}
        options={submoduleOptions} onChange={value=>applyFilter("sub_module",value)}
        ariaLabel="Filter by sub-module" className="ed-delivery-filter-select"/>
    </div>
    <div className="ed-filter-label"><span>Severity</span>
      <CompactMenuSelect value={filters.severity??""}
        options={severityOptions} onChange={value=>applyFilter("severity",value)}
        ariaLabel="Filter by severity" className="ed-delivery-filter-select"/>
    </div>
    <div className="ed-filter-label"><span>Assignee</span>
      <CompactMenuSelect value={filters.assignee??""}
        options={assigneeOptions} onChange={value=>applyFilter("assignee",value)}
        ariaLabel="Filter by assignee" className="ed-delivery-filter-select"/>
    </div>
    <a href="/delivery" className="ed-reset">Reset</a>
  </div>;
}
function WorkInFlight({data,open}:{
  data:DeliveryDashboard;open:(target:DrillTarget)=>void;
}){
  const rows=[...data.flow.wip_by_status].sort((a,b)=>b.issue_count-a.issue_count);
  const total=data.flow.flow_counts.open_total;
  const largest=Math.max(1,...rows.map(row=>row.issue_count));
  const blocked=data.flow.flow_counts.blocked_all;
  const palette=["#3d64cf","#6888e3","#85a1eb","#a3b6e9","#b9c8eb","#cad4e8","#d5dce9"];
  const statusLabel=(status:string)=>status==="Blocked/Onhold"?"Blocked / On hold":status;
  const openStatus=(status:string)=>open({
    key:"status:"+status,label:statusLabel(status),sprintId:data.selected_sprint_id,
  });
  return <Surface title="Work in flight" subtitle="Current status distribution · counts and proportions from the same verified Jira population">
    <div className="ed-wip-content">
      <div className="ed-wip-overview">
        <div className="ed-wip-total"><strong>{num(total)}</strong>
          <span>open issues</span><small>across {num(rows.length)} statuses</small></div>
        <button type="button" className="ed-wip-blocked" onClick={()=>openStatus("Blocked/Onhold")}
          aria-label={num(blocked)+" blocked issues. View the matching Jira issues."}>
          <span className="ed-wip-blocked-dot" aria-hidden="true"/>
          <strong>{num(blocked)}</strong><span>blocked</span>
        </button>
      </div>
      <div className="ed-wip-distribution" role="img"
        aria-label={"Distribution of "+num(total)+" open issues by Jira status"}>
        {rows.map((row,index)=><span key={row.status_name}
          className={"ed-wip-segment"+(row.status_name==="Blocked/Onhold"?" is-blocked":"")}
          style={{width:Math.max(0,row.pct)+"%",backgroundColor:row.status_name==="Blocked/Onhold"?"#d77d72":palette[index%palette.length]}}
          title={statusLabel(row.status_name)+": "+num(row.issue_count)+" issues, "+pct(row.pct)+" of open work"}/>)}
      </div>
      <div className="ed-wip-columns" aria-hidden="true">
        <span>Status</span><span>Relative volume</span><span>Issues</span><span>Share</span>
      </div>
      <div className="ed-wip-list" role="list" aria-label="Open Jira issues by status">
        {rows.map((row,index)=>{
          const blockedRow=row.status_name==="Blocked/Onhold";
          const name=statusLabel(row.status_name);
          return <div role="listitem" key={row.status_name}>
            <button type="button" className={"ed-wip-entry"+(blockedRow?" is-blocked":"")}
              onClick={()=>openStatus(row.status_name)}
              title={name+": "+num(row.issue_count)+" open issues ("+pct(row.pct)+" of all open work). Open the matching Jira issues."}
              aria-label={name+": "+num(row.issue_count)+" open issues, "+pct(row.pct)+" of queue. View Jira issues."}>
              <span className="ed-wip-entry-name">
                <i className="ed-wip-dot" aria-hidden="true"
                  style={{backgroundColor:blockedRow?"#d77d72":palette[index%palette.length]}}/>
                {name}
              </span>
              <span className="ed-wip-entry-track" aria-hidden="true">
                <span style={{width:(row.issue_count/largest*100)+"%",
                  backgroundColor:blockedRow?"#d77d72":palette[index%palette.length]}}/>
              </span>
              <strong className="ed-wip-entry-count">{num(row.issue_count)}</strong>
              <span className="ed-wip-entry-percent">{pct(row.pct)}</span>
            </button>
          </div>;
        })}
      </div>
      <p className="ed-wip-footer">All {num(total)} open issues are assigned to exactly one current Jira status. Select a row to inspect the underlying issues.</p>
    </div>
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
              })}>{num(count)}</button>
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
  const [active,setActive]=useState<number|null>(null);
  const series=[...data.flow.backlog_trend].filter(row=>Number.isFinite(row.open_eod))
    .sort((a,b)=>a.week_start.localeCompare(b.week_start)).slice(-20);
  const n=series.length;
  const latest=n?series[n-1]:null;
  const change=n>=2?series[n-1].open_eod-series[0].open_eod:null;
  const width=760,height=218,left=43,right=14,top=20,bottom=32;
  const values=series.map(row=>row.open_eod);
  const vMin=n?Math.min(...values):0,vMax=n?Math.max(...values):1;
  const range=Math.max(1,vMax-vMin);
  const lo=n?Math.max(0,Math.floor((Math.min(...values)-range*.14)/25)*25):0;
  const hi=n?Math.max(lo+25,Math.ceil((Math.max(...values)+range*.14)/25)*25):25;
  const plotBottom=height-bottom;
  const x=(index:number)=>left+index/Math.max(1,n-1)*(width-left-right);
  const y=(value:number)=>top+(1-(value-lo)/(hi-lo))*(plotBottom-top);
  const path=series.map((row,index)=>(index===0?"M":"L")+x(index).toFixed(1)+","+y(row.open_eod).toFixed(1)).join(" ");
  const area=n>1?path+" L"+x(n-1).toFixed(1)+","+plotBottom+" L"+x(0).toFixed(1)+","+plotBottom+" Z":"";
  const marked=active===null?null:series[active];
  const hitWidth=(width-left-right)/Math.max(1,n-1);
  const ticks=n>=4?[0,Math.floor((n-1)/2),n-1]:n>=2?[0,n-1]:[];
  const changeText=(value:number)=>value>0?"+"+num(value):num(value);
  return <Surface title="Backlog trajectory"
    subtitle="End-of-week open issues · last 20 reported weeks" half>
    <div className="ed-trend-layout">
      <div className="ed-trend-summary">
        <div><span>Latest reported backlog</span>
          <strong>{num(latest?.open_eod)}<small>open issues</small></strong></div>
        <span className={"ed-trend-change"+(change!==null&&change>0?" is-increase":"")}>
          {change===null?"Not enough weeks":changeText(change)+" since first shown week"}
        </span>
      </div>
      {n>=2?<div className="ed-trend-plot" role="group" tabIndex={0}
          aria-label={"Weekly open backlog across "+n+" weeks. Focus, then use left and right arrow keys to inspect."}
          onFocus={()=>setActive(index=>index===null?n-1:index)}
          onBlur={()=>setActive(null)}
          onMouseLeave={()=>setActive(null)}
          onKeyDown={event=>{
            if(event.key==="ArrowLeft"||event.key==="ArrowRight"){
              event.preventDefault();
              setActive(index=>Math.min(n-1,Math.max(0,(index??n-1)+(event.key==="ArrowLeft"?-1:1))));
            }
          }}>
        <svg viewBox={"0 0 "+width+" "+height} role="img"
          aria-label={"Open issues rose or fell across the displayed weeks, from "+
            num(series[0].open_eod)+" to "+num(series[n-1].open_eod)}>
          <defs>
            <linearGradient id="ed-backlog-area" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#4974e8" stopOpacity=".18"/>
              <stop offset="100%" stopColor="#4974e8" stopOpacity=".015"/>
            </linearGradient>
          </defs>
          {[0,.5,1].map(f=>{
            const value=lo+(hi-lo)*f;
            return <g key={f}>
              <line x1={left} x2={width-right} y1={y(value)} y2={y(value)}
                stroke="#e7ecf4" strokeWidth="1"/>
              <text x={left-9} y={y(value)+4} textAnchor="end"
                fontSize="11" fill="#8b99ad">{num(Math.round(value))}</text>
            </g>;
          })}
          <path d={area} fill="url(#ed-backlog-area)"/>
          <path d={path} fill="none" stroke="#416de8" strokeWidth="2.8"
            strokeLinejoin="round" strokeLinecap="round"/>
          {active!==null&&marked?<g>
            <line x1={x(active)} x2={x(active)} y1={top} y2={plotBottom}
              stroke="#9db2df" strokeDasharray="4 5" strokeWidth="1"/>
            <circle cx={x(active)} cy={y(marked.open_eod)} r="5"
              fill="#fff" stroke="#315fda" strokeWidth="3"/>
          </g>:null}
          <circle cx={x(n-1)} cy={y(series[n-1].open_eod)} r="3.5"
            fill="#315fda" stroke="#fff" strokeWidth="1.5"/>
          {series.map((row,index)=><rect key={row.week_start}
            x={Math.max(left,x(index)-hitWidth/2)} y={top}
            width={Math.min(hitWidth,width-right-Math.max(left,x(index)-hitWidth/2))}
            height={plotBottom-top} fill="transparent"
            onMouseEnter={()=>setActive(index)}
            onPointerMove={()=>setActive(index)} aria-hidden="true"/>)}
          {ticks.map((index,i)=><text key={index} x={x(index)} y={height-8}
            textAnchor={i===0?"start":i===ticks.length-1?"end":"middle"}
            fontSize="11" fill="#8595ad">{date(series[index].week_start)}</text>)}
        </svg>
        {active!==null&&marked?<div className="ed-chart-tooltip ed-trend-tooltip"
          role="tooltip"
          style={{left:Math.min(82,Math.max(18,x(active)/width*100))+"%"}}>
          <strong>Week of {date(marked.week_start)}</strong>
          <span><b>{num(marked.open_eod)}</b> open issues</span>
          <small>{num(marked.created)} created · {num(marked.resolved)} resolved</small>
          <small>Net movement: {changeText(marked.net_movement)}</small>
        </div>:null}
      </div>:<p className="ed-chart-empty">Not enough published weeks to plot the backlog trend.</p>}
      <p className="ed-trend-note">Focus the chart and use ← → to inspect each week.</p>
    </div>
  </Surface>;
}
function BugAging({data}:{data:DeliveryDashboard}){
  const [active,setActive]=useState<number|null>(null);
  const rows=data.flow.bug_health.age_histogram;
  const total=data.flow.bug_health.open_bugs;
  const median=data.flow.bug_health.median_age_days;
  return <Surface title="Open bug aging"
    subtitle="Time since Jira issue creation · current non-deleted bug backlog" half>
    <div className="ed-aging">
      <div className="ed-aging-summary">
        <div><span>Open bugs</span><strong>{num(total)}</strong></div>
        <div><span>Median age</span><strong>{decimal(median)}<small> days</small></strong></div>
      </div>
      <div className="ed-aging-chart" role="group" aria-label="Open bug aging by time since creation">
        {rows.map((row,index)=><div className="ed-aging-row" key={row.bucket}
          tabIndex={0} role="group"
          aria-label={row.bucket+": "+num(row.count)+" open bugs, "+pct(row.pct)+" of the total"}
          onMouseEnter={()=>setActive(index)}
          onMouseLeave={()=>setActive(null)}
          onFocus={()=>setActive(index)}
          onBlur={()=>setActive(null)}>
          <span className="ed-aging-label">{row.bucket}</span>
          <span className="ed-aging-track" aria-hidden="true">
            <i style={{width:Math.max(0,Math.min(100,row.pct))+"%"}}/>
          </span>
          <strong>{num(row.count)}</strong>
          <small>{pct(row.pct)}</small>
          {active===index?<div className="ed-chart-tooltip ed-aging-tooltip"
              id="ed-aging-tooltip" role="tooltip">
            <strong>{row.bucket}</strong>
            <span>{num(row.count)} open bugs</span>
            <small>{pct(row.pct)} of the current bug backlog</small>
          </div>:null}
        </div>)}
      </div>
      <p className="ed-aging-note">Hover or focus a range to inspect its count and share.</p>
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
  const cohort=(key:string)=>c[key]?.n??null;
  const metricAction=(key:string)=>c[key]?.n!=null?key:undefined;
  const throughput=data.core.sprint_throughput.find(x=>x.sprint_id===first.sprint_id);
  const gap=first.committed-first.committed_done;
  const q=data.quality.metric_updates;
  // Code Review is always calculated for the displayed sprint's stage
  // history. The dedicated issue evidence is independently reconciled to
  // that same median and population, including historical sprint filters.
  const reviewStage=data.flow.stage_summary.find(row=>
    row.sprint_id===first.sprint_id && row.stage==="Code Review");
  const reviewCount=reviewStage?.issues_in_stage??null;
  const reviewHours=reviewStage?.median_hours??null;
  const sprintMetrics:Metric[]=[
    {id:"commitment",label:"Sprint commitment",period:shortSprint(first.sprint_name),
      value:pct(first.commitment_completion_pct),caption:num(first.committed_done)+" of "+num(first.committed)+" committed issues completed",

      definition:"Completed committed issues divided by all originally committed direct sprint issues. Commitment uses the sprint-start plus two-day cutoff; removed-before-cutoff items are excluded.",
      source:"jira.v_sprint_discipline · verified sprint cohort",
      drillKey:metricAction("commit_s45"),sprintId:filters.sprint,attention:true},
    {id:"commitment_gap",label:"Committed work not delivered",period:shortSprint(first.sprint_name),
      value:num(gap),unit:"issues",caption:"Committed by cutoff · currently not Done",

      definition:"Original committed direct sprint issues minus those currently Done. The issue population matches the sprint discipline removal cutoff.",
      source:"jira.v_sprint_discipline + filtered sprint issue evidence",drillKey:"commitment_gap",sprintId:filters.sprint},
    {id:"mid_sprint",label:"Mid-sprint additions",period:shortSprint(first.sprint_name),value:num(first.added_mid_sprint),unit:"issues",
      caption:pct(first.mid_sprint_add_pct)+" of current sprint scope",
      definition:"Direct sprint issues created after the sprint-start plus two-day commitment cutoff, within the published sprint population.",
      source:"jira.v_sprint_discipline / adds_s45 published cohort",drillKey:metricAction("adds_s45"),sprintId:filters.sprint},
    {id:"throughput",label:"Throughput",period:shortSprint(first.sprint_name),value:num(throughput?.throughput),unit:"completed",
      caption:num(throughput?.first_done_after_start)+" first completed after sprint start",

      definition:"Distinct Jira issues first completed during the sprint reporting window. This is a throughput measure, not the count currently Done in sprint scope.",
      source:"jira.v_sprint_throughput / throughput_s45 published cohort",
      drillKey:metricAction("throughput_s45"),sprintId:filters.sprint},
  ];
  const fc=data.flow.flow_counts;
  const attention:Metric[]=[
    {id:"stale",label:"Stale work",period:"7+ days",value:num(fc.stale_all),unit:"issues",
      caption:"Open issues not updated for 7+ days",
      definition:"Open issues whose last Jira update is older than seven days. Deleted Jira issues are excluded.",
      source:"jira.v_issue_flow_state / stale_7d cohort",drillKey:metricAction("stale_7d")},
    {id:"stale_blocked",label:"Stale and blocked",period:"7+ days",value:num(fc.stale_blocked),unit:"issues",
      caption:"Blocked status and stale for 7+ days",

      definition:"Open issues with status Blocked/Onhold and no Jira update in the past seven days.",
      source:"jira.v_flow_counts / stale_blocked cohort",drillKey:metricAction("stale_blocked")},
    {id:"l1",label:"Open L1 bugs",period:"L1",value:num(cohort("open_l1_s45")),unit:"bugs",
      caption:"Open issues classified L1 · untagged retained elsewhere",

      definition:"Not-Done Jira bug issues explicitly tagged with severity L1. Issues missing severity remain in total open bugs, not this segment.",
      source:"jira.v_metric_cohorts_active_v1 / open_l1_s45",drillKey:metricAction("open_l1_s45")},
    {id:"qa_queue",label:"QA queue",period:"Current",value:num(fc.open_total>=0?cohort("qa_queue"):null),unit:"open",
      caption:"Open issues awaiting UAT, testing or staging exit",

      definition:"Open issues currently in UAT, Testing or Staging, matching the audited QA queue population.",
      source:"jira.v_qa_queue / qa_queue cohort",drillKey:metricAction("qa_queue")},
    {id:"blocked",label:"Blocked",period:"Current",value:num(fc.blocked_all),unit:"issues",
      caption:pct(fc.open_total?fc.blocked_all/fc.open_total*100:null)+" of current open work",

      definition:"Open Jira issues currently in Blocked/Onhold. Denominator is all currently open, non-deleted issues.",
      source:"jira.v_flow_counts / blocked cohort",drillKey:metricAction("blocked"),attention:true},
  ];
  const qReopen=q.reopen_latest, qReject=q.qa_rejection,qResolution=q.bug_resolution,qTurn=q.qa_turnaround;
  const bugAging=data.flow.bug_health;
  const quality:Metric[]=[
    {id:"bugs",label:"Open bug backlog",period:"Current",value:num(bugAging.open_bugs),unit:"open bugs",
      caption:"Median age "+decimal(bugAging.median_age_days)+"d",

      definition:"Jira issues of type Bug not in Done status, excluding Jira-deleted issues. Median age is measured from creation.",
      source:"jira.v_bug_health / open_bugs cohort",drillKey:metricAction("open_bugs")},
    {id:"reopen",label:"Reopen rate",period:"Latest month",value:pct(qReopen?.value),caption:num(qReopen?.n)+" of "+num(qReopen?.denominator)+" closes · latest observed month",

      definition:"Reopened issues relative to the published closed-issue denominator for the latest measured month. Historical status changes are used.",
      source:"jira.get_filtered_dashboard_quality_submodule / reopen_latest cohort",drillKey:metricAction("reopen_latest")},
    {id:"qa_reject",label:"QA rejection",period:"All time",value:pct(qReject?.value,2),caption:num(qReject?.n)+" rejected cycles of "+num(qReject?.denominator)+" decisions",

      definition:"Rejected UAT cycles divided by accepted plus rejected UAT decisions. The rate counts decisions; the issue drill lists distinct affected issue records.",
      source:"jira.v_qa_rejection_org / qa_rejection cohort",drillKey:metricAction("qa_rejection")},
    {id:"bug_resolution",label:"Bug resolution",period:"All time",value:decimal(qResolution?.value,2)+"d",
      caption:"Median created → resolved · "+num(qResolution?.n)+" bugs",

      definition:"Median elapsed days from Jira bug creation to its published resolved timestamp, using the filtered resolved-bug population.",
      source:"jira.v_resolution_medians / bug_resolution cohort",drillKey:metricAction("bug_resolution")},
    {id:"qa_turn",label:"QA turnaround",period:"All time",value:decimal(qTurn?.value!=null?qTurn.value/24:null,1)+"d",
      caption:"Median UAT stay · "+num(qTurn?.n)+" measured",

      definition:"Median hours from UAT entry to a recorded exit decision, displayed in days (hours divided by 24). Incomplete/open windows are excluded.",
      source:"jira.v_resolution_medians / qa_turnaround cohort",drillKey:metricAction("qa_turnaround")},
    {id:"code_review",label:"Code review",period:shortSprint(first.sprint_name),value:hrs(reviewHours),caption:"Median stage dwell · "+shortSprint(first.sprint_name),

      definition:"Median accumulated time in Code Review per issue, for the displayed sprint. Issues can revisit review; their recorded stage intervals are summed. The evidence median and population are independently reconciled before display.",
      source:"jira.v_sprint_stage_summary / exact Code Review stage-history evidence",
      drillKey:reviewCount!==null?"stage:Code Review":undefined,sprintId:first.sprint_id},
  ];
  const apply=(m:Metric)=>setInfo(m);
  const drillTo=(d:DrillTarget)=>setDrill(d);
  return <>
    <main className="rd-page ed-page">
      <div className="rd-page-head ed-page-head">
        <div className="ed-page-copy">
          <h1>Engineering &amp; Delivery</h1>
          <p>Sprint delivery, attention, flow and quality</p>
        </div>
        <FilterBar data={data} filters={filters}/>
      </div>

      <section className="metrics-grid-section ed-section" aria-label="Sprint delivery">
        <SectionHead title="Sprint delivery" question="Did we finish the work we planned?"/>
        <div className="ed-sprint-kpis ed-kpi-grid po-kpis">{sprintMetrics.map(m=>
          <MetricTile key={m.id} metric={m} onInfo={apply} onDrill={drillTo}/>)}</div>
      </section>
      <section className="metrics-grid-section ed-section" aria-label="Attention">
        <SectionHead title="Attention" question="Work requiring action now"/>
        <div className="ed-attention-kpis ed-kpi-grid po-kpis">{attention.map(m=>
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
        <div className="ed-quality-kpis ed-kpi-grid po-kpis">{quality.map(m=>
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
    {drill?<DeliveryEvidenceModal target={drill} data={data} filters={filters} onClose={()=>setDrill(null)}/>:null}
  </>;
}
