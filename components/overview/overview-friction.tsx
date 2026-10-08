"use client";

import {useEffect,useRef,useState} from "react";
import {createPortal} from "react-dom";
import type {OverviewUsageSnapshot} from "../../lib/overview/kpis";
import type {FrictionSummary,FrictionKey,FrictionPeriod,FrictionSegment} from "../../lib/overview/friction";
import FrictionDrillModal,{type FrictionTarget} from "./overview-friction-modals";

const number=new Intl.NumberFormat("en-US");
function formatPercent(n:number|null):string{
 return n===null?"—":n.toFixed(1)+"%";
}
function IssueInfo({onClose}:{onClose:()=>void}){
 const close=useRef<HTMLButtonElement>(null);
 useEffect(()=>{
  close.current?.focus({preventScroll:true});
  const keydown=(e:KeyboardEvent)=>{if(e.key==="Escape"){e.preventDefault();onClose();}};
  window.addEventListener("keydown",keydown);
  return ()=>window.removeEventListener("keydown",keydown);
 },[onClose]);
 return <div className="rd-overlay" role="presentation">
  <section className="rd-modal rd-activation-modal po-friction-info-modal"
   role="dialog" aria-modal="true" aria-labelledby="po-friction-info-title">
   <header className="rd-modal-head">
    <div><p>Product Overview · Measurement definitions</p>
     <h2 id="po-friction-info-title">Issues that need attention</h2>
     <span>Event-backed company signals · Same source cutoff as the rest of Overview</span>
    </div>
    <button ref={close} type="button" className="rd-close"
     onClick={onClose} aria-label="Close issue definitions">
     <svg className="rd-icon" aria-hidden="true"><use href="#i-close"/></svg>
    </button>
   </header>
   <div className="po-friction-info-body">
    <h3>Company-based incidence</h3>
    <p>The numerator is distinct client companies with an explicitly tracked failed
     action or a deliberate revert to Needs Review. The denominator is distinct
     client companies that attempted that same workflow in the same rolling
     28-day period, whether successful or failed.</p>
    <h3>Later success, not confirmed resolution</h3>
    <p>A company is in “Later success” when a successful event in the same workflow
     occurred after its latest failure/reversion, within that same reporting window.
     “Needs review” means no such later success was observed by the period end.
     These are company-level signals, not confirmed fixes to the original transaction
     or file. The event instrumentation does not provide a consistent item identifier
     to make that stronger claim.</p>
    <h3>What each issue means</h3>
    <p>Bill and invoice uploads, ledger updates, and transaction-type updates
     require an explicit failed status. “Reverted to review” is the deliberate
     Transaction Status action “Revert to Needs Review”; it indicates rework,
     not a product error. A subsequent “Accounting Ready” event in the same
     company counts as a later workflow success.</p>
    <h3>Reporting period and exclusions</h3>
    <p>Current and previous windows are adjacent 28-day periods, ending at the
     published Overview cutoff. Events ingested after the source watermark,
     internal users, and non-client companies are excluded. Companies may appear
     under multiple issue categories. The table is ordered by current companies
     needing review, not event volume.</p>
   </div>
  </section>
 </div>;
}

export default function OverviewFriction({
 summary,usageSnapshot,target,
}:{
 summary:FrictionSummary|null;usageSnapshot:OverviewUsageSnapshot|null;
 target:HTMLElement;
}){
 const [asOfDate,setAsOfDate]=useState(usageSnapshot?.asOfDate??"");
 const [drill,setDrill]=useState<FrictionTarget|null>(null);
 const [info,setInfo]=useState(false);
 const lastTrigger=useRef<HTMLElement|null>(null);
 useEffect(()=>{
  const onDate=(event:Event)=>{
   const value=(event as CustomEvent<{asOf:string}>).detail?.asOf;
   if(typeof value==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(value))setAsOfDate(value);
  };
  window.addEventListener("aia:overview-asof",onDate);
  return ()=>window.removeEventListener("aia:overview-asof",onDate);
 },[]);
 const ready=Boolean(summary&&usageSnapshot
  &&summary.snapshotId===usageSnapshot.snapshotId
  &&Date.parse(summary.asOf)===Date.parse(usageSnapshot.asOf)
  &&asOfDate===usageSnapshot.asOfDate);
 useEffect(()=>{
  const foot=document.getElementById("po-friction-foot");
  if(foot)foot.textContent=ready
   ?"Company-level signals · Later success is not confirmed resolution"
   :"Verified data unavailable for this reporting date";
 },[ready]);
 useEffect(()=>{
  const button=document.querySelector<HTMLElement>(
   '#po-friction-report [data-po-info="friction"]'
  );
  if(!button)return;
  const click=(event:MouseEvent)=>{
   event.preventDefault();
   event.stopImmediatePropagation();
   lastTrigger.current=button;
   setInfo(true);
  };
  button.addEventListener("click",click,true);
  return ()=>button.removeEventListener("click",click,true);
 },[target]);
 function open(issue:FrictionKey,segment:FrictionSegment,
  event:React.MouseEvent<HTMLButtonElement>,period:FrictionPeriod="current"){
  if(!ready)return;
  lastTrigger.current=event.currentTarget;
  setDrill({key:issue,segment,period});
 }
 function close(){
  setDrill(null);setInfo(false);
  requestAnimationFrame(()=>lastTrigger.current?.focus({preventScroll:true}));
 }
 const body=!ready||!summary
  ?<div className="po-friction-empty" role="status">
    <strong>Live issue metrics unavailable</strong>
    <span>No published company records for this reporting date.</span>
   </div>
  :<div className="po-data-wrap">
    <table className="po-data-table po-friction-table po-friction-live-table">
     <thead><tr>
      <th scope="col">Issue</th>
      <th scope="col">Incidence</th>
      <th scope="col">vs previous</th>
      <th scope="col">Later success</th>
      <th scope="col">Needs review</th>
     </tr></thead>
     <tbody>{summary.rows.map(row=>{
      const current=row.current,previous=row.previous;
      const change=row.change_pp;
      const followupRate=current.followup_pct??null;
      return <tr key={row.key}>
       <td>
        <button type="button" className="po-cell-link po-issue-label"
         onClick={e=>open(row.key,"affected",e)}>
         <span>{row.module}</span>
         {row.label}
        </button>
        {row.kind==="Rework"?<small>Intentional workflow rework</small>:null}
       </td>
       <td><button type="button" className="po-cell-link"
        onClick={e=>open(row.key,"affected",e)}>
        <strong>{formatPercent(current.incidence_pct)}</strong>
        <small>{number.format(current.affected)} / {number.format(current.eligible)} companies</small>
       </button></td>
       <td><button type="button" className="po-cell-link po-friction-change"
        onClick={e=>open(row.key,"affected",e,"previous")}>
        <strong className={change===null?"":change>0?"po-friction-bad":"po-friction-good"}>
         {change===null?"—":(change>0?"+":"")+change.toFixed(1)+" pp"}
        </strong>
        <small>prev. {formatPercent(previous.incidence_pct)}</small>
       </button></td>
       <td>
        <button type="button" className="po-recovery po-cell-link"
         onClick={e=>open(row.key,"later_success",e)}>
         <span className="po-bar-track" aria-hidden="true">
          <i style={{width:(followupRate??0)+"%"}}/>
         </span>
         <span className="po-recovery-text">
          <strong>{formatPercent(followupRate)}</strong>
          <small>{current.followup} of {current.affected}</small>
         </span>
        </button>
       </td>
       <td><button type="button" className="po-cell-link"
        aria-label={number.format(current.needs_review)+
         " "+row.label+" companies without a later successful workflow event"}
        onClick={e=>open(row.key,"needs_review",e)}>
        <strong className={"po-issue-open"+(current.needs_review?"":" clear")}>
         {number.format(current.needs_review)}
        </strong>
       </button></td>
      </tr>;
     })}</tbody>
    </table>
   </div>;
 return <>
  {createPortal(body,target)}
  {drill&&summary&&typeof document!=="undefined"?
   createPortal(<FrictionDrillModal
    key={drill.key+":"+drill.period+":"+drill.segment}
    summary={summary} target={drill} onClose={close}/>,
    document.body):null}
  {info&&typeof document!=="undefined"?
   createPortal(<IssueInfo onClose={close}/>,document.body):null}
 </>;
}
