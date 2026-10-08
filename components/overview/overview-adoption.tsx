"use client";

import { useEffect,useRef,useState } from "react";
import { createPortal } from "react-dom";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type {
 AdoptionSummary,AdoptionOutcome,AdoptionStage,AdoptionModule,AdoptionStep,AdoptionSegment,
} from "../../lib/overview/adoption";
import AdoptionDrillModal,{type AdoptionDrillTarget} from "./overview-adoption-modals";
import { OverviewInfoButton } from "./overview-info";

const nf=new Intl.NumberFormat("en-US");
function rate(n:number,d:number){
 return d>0?(n*100/d).toFixed(1)+"%":"—";
}
function date(value:string){
 return new Intl.DateTimeFormat("en-GB",{
  timeZone:"Asia/Kolkata",day:"numeric",month:"short",year:"numeric",
 }).format(new Date(value));
}
function Notice({message}:{message:string}){
 return <div className="po-adoption-unavailable">
  <strong>Live adoption data unavailable</strong><span>{message}</span>
 </div>;
}
const outcomeMeta:Array<{
 key:AdoptionOutcome;title:string;period:string;note:string;formula:string;
 neg:AdoptionSegment;tabs:[string,string];
}>=[
 {key:"core_7d",title:"7-day core adoption",period:"First 7 days",
  note:"Started independent accounting work",formula:"Independent core work within 7 days of integration",
  neg:"not_core_7d",tabs:["Started work","Did not start"]},
 {key:"value_28d",title:"28-day value conversion",period:"First 28 days",
  note:"Completed the four-step value milestone",
  formula:"Training sync → later-day independent core → confirming sync",
  neg:"not_value_28d",tabs:["Reached value","Not yet converted"]},
 {key:"sustained_28d",title:"28-day sustained adoption",period:"First four weeks",
  note:"Core work in at least two weeks",
  formula:"Independent core activity in 2+ of first 4 integration-relative weeks",
  neg:"not_sustained_28d",tabs:["Sustained","Not sustained"]},
];
const stages:Array<{key:AdoptionStage;label:string;description:string}>= [
 {key:"integration",label:"Successful integration",
  description:"Recorded Tally or Zoho integration"},
 {key:"started_work",label:"Started accounting work",
  description:"Independent core activity in the first 7 days"},
 {key:"qualifying_sync",label:"Qualifying accounting sync",
  description:"Sync after first-week core work, within 28 days"},
];
const modules:Array<{
 key:AdoptionModule;label:string;steps:Array<{key:AdoptionStep;label:string}>;
}>=[
 {key:"ap",label:"Bills / AP",steps:[
  {key:"bill_upload",label:"Bill uploaded"},
  {key:"bill_entity",label:"Bill record created"},
  {key:"vendor_mismatch",label:"Vendor mismatch resolved"},
 ]},
 {key:"ar",label:"Invoices / AR",steps:[
  {key:"invoice_upload",label:"Invoice uploaded"},
  {key:"invoice_entity",label:"Invoice record created"},
  {key:"invoice_bulk",label:"Invoice bulk edited"},
 ]},
 {key:"transactions",label:"Statements / Transactions",steps:[
  {key:"statement_upload",label:"Statement uploaded"},
  {key:"transaction_ledger",label:"Ledger updated"},
  {key:"transaction_status",label:"Transaction status updated"},
  {key:"transaction_type",label:"Transaction type updated"},
 ]},
];
function tab(key:AdoptionSegment,label:string,count:number){
 return {key,label,count};
}
function targetForOutcome(data:AdoptionSummary,key:AdoptionOutcome):AdoptionDrillTarget{
 const m=outcomeMeta.find(x=>x.key===key)!;
 return {
  title:m.title,context:m.formula,initial:key,
  tabs:[
   tab(key,m.tabs[0],data.outcomes[key]),
   tab(m.neg,m.tabs[1],data.total-data.outcomes[key]),
   tab("all","All",data.total),
  ],
 };
}
function targetForStage(data:AdoptionSummary,key:AdoptionStage):AdoptionDrillTarget{
 const title=stages.find(x=>x.key===key)!.label;
 return {
  title,context:stages.find(x=>x.key===key)!.description,
  initial:key==="integration"?"all":key==="started_work"?"core_7d":"qualifying_sync",
  tabs:key==="integration"?[
   tab("all","All integrated",data.total),
   tab("core_7d","Started work",data.stages.started_work),
   tab("stalled_after_integration","Did not start",data.total-data.stages.started_work),
  ]:[
   tab("core_7d","Started work",data.stages.started_work),
   tab("qualifying_sync","Reached sync",data.stages.qualifying_sync),
   tab("stalled_before_sync","Awaiting sync",
    data.stages.started_work-data.stages.qualifying_sync),
  ],
 };
}
function targetForModule(data:AdoptionSummary,module:AdoptionModule):AdoptionDrillTarget{
 const m=modules.find(x=>x.key===module)!;
 return {
  title:m.label,context:"Overlapping module participation among first-week starters",
  initial:("module_"+module) as AdoptionSegment,
  tabs:[
   tab(("module_"+module) as AdoptionSegment,m.label,data.modules[module]),
   tab("core_7d","All starters",data.outcomes.core_7d),
   tab("all","All integrated",data.total),
  ],
 };
}
function targetForStep(data:AdoptionSummary,step:AdoptionStep,module:AdoptionModule):AdoptionDrillTarget{
 const m=modules.find(x=>x.key===module)!;
 const item=m.steps.find(x=>x.key===step)!;
 return {
  title:item.label,context:"Observed activity during first 28 days after integration",
  initial:step,tabs:[
   tab(step,"Matched",data.steps[step]),
   tab(("module_"+module) as AdoptionSegment,m.label,data.modules[module]),
   tab("core_7d","All starters",data.outcomes.core_7d),
  ],
 };
}
function OutcomeCards({
 summary,ready,onDrill,
}:{
 summary:AdoptionSummary|null;ready:boolean;
 onDrill:(target:AdoptionDrillTarget,trigger:HTMLElement)=>void;
}){
 return <>
  {outcomeMeta.map(meta=>{
   const count=ready&&summary?summary.outcomes[meta.key]:null;
   const pct=count!==null&&summary?rate(count,summary.total):"—";
   return <div className="po-kpi-info-wrap" key={meta.key}>
    <button className="metric-card" type="button"
    aria-haspopup="dialog"
    aria-label={meta.title+": "+pct+". Open company drill-down"}
    onClick={e=>{
     if(ready&&summary)onDrill(targetForOutcome(summary,meta.key),e.currentTarget);
    }}>
    <span className="po-kpi-divider" aria-hidden="true"/>
    <span className="metric-label">{meta.title}</span>
    <span className="metric-period">{meta.period}</span>
    <span className="metric-value">{pct}</span>
    <span className="metric-note">{count!==null&&summary?
      nf.format(count)+" of "+nf.format(summary.total)+" integrated companies":
      "Published data unavailable"}</span>
    <span className="po-change">{meta.note}</span>
   </button>
    <OverviewInfoButton infoKey={meta.key}/>
   </div>;
  })}
 </>;
}
function Funnel({
 summary,ready,onDrill,expanded=false,
}:{
 summary:AdoptionSummary|null;ready:boolean;expanded?:boolean;
 onDrill:(target:AdoptionDrillTarget,trigger:HTMLElement)=>void;
}){
 const [module,setModule]=useState<AdoptionModule>("ap");
 if(!summary||!ready)return <Notice message="Select the latest reporting date to see verified cohort results."/>;
 const moduleDef=modules.find(x=>x.key===module)!;
 return <div className={"po-adoption-funnel"+(expanded?" is-expanded":"")}>
  <div className="po-journey-table" role="group" aria-label="Integration journey funnel">
   <div className="po-journey-heading">
    <span>Next step</span>
    <span className="po-total-heading">Total</span>
    <span>Next step<br/>conversion</span>
    <span>To stage<br/>cumulative conversion</span>
   </div>
   {stages.map((stage,index)=>{
    const count=summary.stages[stage.key];
    const prior=index?summary.stages[stages[index-1].key]:summary.total;
    const fill=summary.total?count*100/summary.total:0;
    const next=index?rate(count,prior):"100%";
    const overall=rate(count,summary.total);
    return <div className={"po-journey-row po-journey-row-"+index}
     key={stage.key}>
     <button className="po-journey-stage-button" type="button"
      aria-label={stage.label+": "+nf.format(count)+" companies. View cohort."}
      onClick={e=>onDrill(targetForStage(summary,stage.key),e.currentTarget)}>
      <span className="po-journey-stage-name">
       <span className="po-journey-number">{index+1}</span>
       <strong>{stage.label}</strong>
       <small>{stage.description}</small>
      </span>
      <span className="po-journey-bar-track">
       <span className="po-journey-bar-fill" style={{width:fill+"%"}}>
        <strong>{nf.format(count)}</strong>
       </span>
      </span>
     </button>
     <button type="button" className="po-journey-chevron"
      aria-label={stage.label+": "+next+" conversion from previous step"}
      onClick={e=>onDrill(targetForStage(summary,stage.key),e.currentTarget)}>
      {next}
     </button>
     <button type="button" className="po-journey-chevron"
      aria-label={stage.label+": "+overall+" cumulative conversion"}
      onClick={e=>onDrill(targetForStage(summary,stage.key),e.currentTarget)}>
      {overall}
     </button>
    </div>;
   })}
  </div>
  <div className="po-journey-module-panel">
   <div className="po-journey-module-heading">
    <div>
     <h3>Accounting work by module</h3>
     <p>Of {nf.format(summary.outcomes.core_7d)} companies that started work · Modules overlap</p>
    </div>
    <span>First 28 days after integration</span>
   </div>
   <div className="po-journey-module-tabs" role="tablist" aria-label="Accounting modules">
    {modules.map(m=><button type="button" role="tab"
     key={m.key} aria-selected={module===m.key}
     onClick={()=>setModule(m.key)}>
     <strong>{m.label}</strong>
     <span>{nf.format(summary.modules[m.key])}
      <small> / {rate(summary.modules[m.key],summary.outcomes.core_7d)}</small>
     </span>
    </button>)}
   </div>
   <div className="po-journey-module-details">
    <div className="po-journey-module-overview">
     <span><strong>{moduleDef.label}</strong> · {nf.format(summary.modules[module])} companies</span>
     <button type="button" onClick={e=>onDrill(targetForModule(summary,module),e.currentTarget)}>
      View companies →
     </button>
    </div>
    {moduleDef.steps.map(step=>{
     const count=summary.steps[step.key];
     const denominator=summary.modules[module];
     const width=denominator?count/denominator*100:0;
     return <button className="po-journey-module-step" type="button" key={step.key}
      onClick={e=>onDrill(targetForStep(summary,step.key,module),e.currentTarget)}>
      <span>{step.label}</span>
      <span className="po-journey-mini-track"><i style={{width:width+"%"}}/></span>
      <strong>{nf.format(count)}</strong>
      <small>{rate(count,denominator)}</small>
     </button>;
    })}
   </div>
  </div>
 </div>;
}
function JourneyExpanded({
 summary,ready,onDrill,onClose,drillOpen,
}:{
 summary:AdoptionSummary|null;ready:boolean;
 onDrill:(target:AdoptionDrillTarget,trigger:HTMLElement)=>void;
 onClose:()=>void;drillOpen:boolean;
}){
 const closeButton=useRef<HTMLButtonElement>(null);
 useEffect(()=>{
  const old=document.body.style.overflow;document.body.style.overflow="hidden";
  closeButton.current?.focus({preventScroll:true});
  return ()=>{document.body.style.overflow=old};
 },[]);
 useEffect(()=>{
  const escape=(e:KeyboardEvent)=>{
   if(e.key==="Escape"&&!drillOpen&&
      !document.querySelector(".po-overview-info-dialog[open]")){
    e.preventDefault();e.stopImmediatePropagation();onClose();
   }
  };
  window.addEventListener("keydown",escape,true);
  return ()=>window.removeEventListener("keydown",escape,true);
 },[drillOpen,onClose]);
 return <div className="po-native-expanded-overlay"
  role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}>
  <section className="po-report-expanded po-native-expanded-report po-adoption-expanded"
   role="dialog" aria-modal="true" aria-labelledby="po-adoption-expanded-title">
   <div className="report-modal-chrome">
    <span id="po-adoption-expanded-title">Integration journey · Expanded view</span>
    <div className="po-expanded-head-actions">
     <button type="button" className="icon-button"
      data-po-help="journey" aria-label="How integration journey is counted"
      title="How it's counted">
      <svg className="icon" aria-hidden="true"><use href="#i-info"/></svg>
     </button>
     <button ref={closeButton} type="button" className="close-button"
      onClick={onClose} aria-label="Close expanded journey">
      <svg className="icon" aria-hidden="true"><use href="#i-close"/></svg>
     </button>
    </div>
   </div>
   <div className="po-expanded-mount">
    <article className="po-report po-full po-journey-funnel-report">
     <header className="po-report-head">
      <div><h2>Integration journey</h2>
       <p className="po-subtitle">Mature integrated cohort · {summary?.total??"—"} companies</p>
      </div>
     </header>
     <div className="po-body"><Funnel summary={summary} ready={ready}
      onDrill={onDrill} expanded/></div>
    </article>
   </div>
  </section>
 </div>;
}
export default function OverviewAdoption({
 summary,usageSnapshot,stripTarget,funnelTarget,
}:{
 summary:AdoptionSummary|null;usageSnapshot:OverviewUsageSnapshot|null;
 stripTarget:HTMLElement;funnelTarget:HTMLElement;
}){
 const [asOfDate,setAsOfDate]=useState(usageSnapshot?.asOfDate??"");
 const [target,setTarget]=useState<AdoptionDrillTarget|null>(null);
 const [expanded,setExpanded]=useState(false);
 const trigger=useRef<HTMLElement|null>(null);
 const expandTrigger=useRef<HTMLButtonElement|null>(null);
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
  const caption=document.getElementById("po-journey-caption");
  if(caption)caption.textContent=ready&&summary
   ? "Mature integrated cohort · "+nf.format(summary.total)+
     " companies · Full 28-day observation"
   : "No verified cohort for this reporting date";
 },[ready,summary]);
 useEffect(()=>{
  const expandButton=document.querySelector<HTMLButtonElement>(
   '#po-journey-report [data-po-expand="po-journey-report"]');
  if(!expandButton)return;
  const expand=(event:Event)=>{
   event.preventDefault();event.stopImmediatePropagation();
   expandTrigger.current=expandButton;setExpanded(true);
  };
  expandButton.addEventListener("click",expand,true);
  return ()=>{
   expandButton.removeEventListener("click",expand,true);
  };
 },[funnelTarget]);
 function openDrill(next:AdoptionDrillTarget,element:HTMLElement){
  if(!ready)return;
  trigger.current=element;setTarget(next);
 }
 function closeDrill(){
  setTarget(null);
  requestAnimationFrame(()=>trigger.current?.focus({preventScroll:true}));
 }
 function closeExpanded(){
  setExpanded(false);
  requestAnimationFrame(()=>expandTrigger.current?.focus({preventScroll:true}));
 }
 return <>
  {createPortal(<OutcomeCards summary={summary} ready={ready}
   onDrill={openDrill}/>,stripTarget)}
  {createPortal(<Funnel summary={summary} ready={ready}
   onDrill={openDrill}/>,funnelTarget)}
  {expanded&&typeof document!=="undefined"?
   createPortal(<JourneyExpanded summary={summary} ready={ready}
    onDrill={openDrill} onClose={closeExpanded} drillOpen={!!target}/>,
    document.body):null}
  {target&&summary&&typeof document!=="undefined"?
   createPortal(<AdoptionDrillModal
    key={target.title+":"+target.initial}
    summary={summary} target={target} onClose={closeDrill}/>,
    document.body):null}
 </>;
}
