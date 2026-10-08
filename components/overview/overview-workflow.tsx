"use client";

import { useEffect,useRef,useState,type RefObject,type CSSProperties } from "react";
import { createPortal } from "react-dom";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type {
 WorkflowSummary,WorkflowWeek,WorkflowModule,WorkflowMask,
} from "../../lib/overview/workflow";
import {
 WorkflowModuleUsersModal,WorkflowMixCompaniesModal,
} from "./overview-workflow-modals";

const nf=new Intl.NumberFormat("en-US");
const MODULES:Array<{key:WorkflowModule;label:string;color:string}>= [
 {key:"ap",label:"AP / Bills",color:"#315de5"},
 {key:"ar",label:"AR / Invoices",color:"#9cbfe8"},
 {key:"transactions",label:"Transactions",color:"#243864"},
];
const COMBINATIONS:Array<{mask:WorkflowMask;label:string}>= [
 {mask:"001",label:"Transactions only"},
 {mask:"100",label:"AP only"},
 {mask:"101",label:"AP + Transactions"},
 {mask:"110",label:"AP + AR"},
 {mask:"111",label:"AP + AR + Transactions"},
 {mask:"010",label:"AR only"},
 {mask:"011",label:"AR + Transactions"},
 {mask:"000",label:"Other core only"},
];
const fmtWeek=new Intl.DateTimeFormat("en-GB",{timeZone:"UTC",day:"numeric",month:"short"});
function day(s:string){
 return new Intl.DateTimeFormat("en-GB",{
  timeZone:"UTC",day:"numeric",month:"short",year:"numeric",
 }).format(new Date(s+"T12:00:00Z"));
}
function week(s:string){
 return fmtWeek.format(new Date(s+"T12:00:00Z"));
}
function weekEnd(s:string){
 return fmtWeek.format(new Date(Date.parse(s+"T12:00:00Z")+6*86_400_000));
}
function dateTime(s:string){
 return new Date(s).toLocaleDateString("en-GB",{timeZone:"Asia/Kolkata",
  day:"numeric",month:"short",year:"numeric"});
}
function percentage(n:number,d:number){
 return d>0?100*n/d:0;
}
function useWidth(ref:RefObject<HTMLDivElement|null>){
 const [w,setW]=useState(550);
 useEffect(()=>{
  const target=ref.current;if(!target)return;
  const measure=()=>setW(Math.max(300,Math.round(target.clientWidth||550)));
  measure();
  const o=typeof ResizeObserver!=="undefined"?new ResizeObserver(measure):null;
  o?.observe(target);window.addEventListener("resize",measure);
  return ()=>{o?.disconnect();window.removeEventListener("resize",measure)};
 },[ref]);
 return w;
}
function Unavailable(){
 return <div className="po-chart-live-empty" role="status">
  <strong>Live workflow data unavailable</strong>
  <span>No verified snapshot for this reporting date.</span>
 </div>;
}

function ModuleTrend({
 data,ready,selected,onSelect,view,onView,onPoint,expanded=false,
}:{
 data:WorkflowSummary|null;ready:boolean;
 selected:WorkflowModule[];onSelect:(key:WorkflowModule)=>void;
 view:"chart"|"table";onView:()=>void;
 onPoint:(point:{week:string;module:WorkflowModule;count:number},element:HTMLElement|SVGElement)=>void;
 expanded?:boolean;
}){
 const ref=useRef<HTMLDivElement>(null);
 const plotRef=useRef<HTMLDivElement>(null);
 const [hovered,setHovered]=useState<{
  week:string;left:number;top:number;pointer:number;below:boolean;
 }|null>(null);
 const width=useWidth(ref);
 useEffect(()=>setHovered(null),[view,selected,expanded]);
 if(!data||!ready)return <Unavailable/>;
 const rows=data.weekly;
 const h=expanded?450:235,left=31,right=10,top=22,bottom=28;
 const plotW=width-left-right,plotH=h-top-bottom;
 const vals=rows.flatMap(row=>selected.map(k=>row[k]));
 const m=Math.max(50,...vals);
 const max=Math.ceil(m*1.12/50)*50;
 const step=plotW/Math.max(1,rows.length-1);
 const xx=(i:number)=>left+i*step;
 const yy=(n:number)=>top+plotH-n/max*plotH;
 const hoveredRow=hovered?rows.find(row=>row.week_start===hovered.week):null;
 function showTooltip(row:WorkflowWeek,node:SVGGElement){
  const plot=plotRef.current;
  const marker=node.querySelector<SVGCircleElement>(".po-workflow-point-marker");
  if(!plot||!marker)return;
  const plotRect=plot.getBoundingClientRect();
  const pointRect=marker.getBoundingClientRect();
  const x=pointRect.left+pointRect.width/2-plotRect.left;
  const y=pointRect.top+pointRect.height/2-plotRect.top;
  const cardWidth=Math.min(205,plotRect.width-16);
  const left=Math.min(plotRect.width-cardWidth-8,Math.max(8,x-cardWidth/2));
  setHovered({
   week:row.week_start,left,top:y,
   pointer:Math.min(cardWidth-15,Math.max(15,x-left)),
   below:y<86,
  });
 }
 function open(row:WorkflowWeek,key:WorkflowModule,node:HTMLElement|SVGElement){
  onPoint({week:row.week_start,module:key,count:row[key]},node);
 }
 return <div ref={ref} className="po-native-workflow-chart">
  <div className="po-legend" aria-label="Visible module series">
   {MODULES.map(s=><button type="button" className="po-workflow-legend-button"
    key={s.key} aria-pressed={selected.includes(s.key)}
    onClick={()=>onSelect(s.key)}>
    <i className={"po-dot "+s.key} style={{background:s.color}}/>
    {s.label}
   </button>)}
   <button type="button" className="po-active-chart-view-toggle"
    onClick={onView}>{view==="chart"?"View table":"View chart"}</button>
  </div>
  {view==="table"?
   <div className={"po-data-view po-live-weekly-table po-workflow-data"+(expanded?" is-expanded":"")}>
    <table className="po-data-table">
     <thead><tr><th>Week starting</th>
      {MODULES.map(s=><th key={s.key}>{s.label}</th>)}
      <th>All active users</th>
     </tr></thead>
     <tbody>{rows.map(r=><tr key={r.week_start}>
      <td>{day(r.week_start)}{r.limited_tracking?" *":""}</td>
      {MODULES.map(s=><td key={s.key}>
       <button type="button" className="po-cell-link"
        onClick={e=>open(r,s.key,e.currentTarget)}>{nf.format(r[s.key])}</button>
      </td>)}
      <td>{nf.format(r.total)}</td>
     </tr>)}</tbody>
    </table>
   </div>:
   <div className="po-workflow-plot" ref={plotRef} onMouseLeave={()=>setHovered(null)}>
   <svg className="po-chart po-workflow-line-svg"
    viewBox={"0 0 "+width+" "+h} role="group"
    aria-label="Weekly distinct core-active users by AP, AR and Transaction modules">
    {Array.from({length:5},(_,i)=>{
     const value=max*i/4,y=yy(value);
     return <g key={i}>
      <line x1={left} y1={y} x2={width-right} y2={y}
       stroke={i===0?"#dfe5ef":"#ecf0f6"}
       strokeDasharray={i===0?undefined:"2 5"}/>
      <text x={left-9} y={y+3} textAnchor="end"
       fontSize={9} fill="#9aa7b9">{Math.round(value)}</text>
     </g>;
    })}
    {rows.map((r,i)=>width>480||i%2===0||i===rows.length-1
     ?<text key={"label:"+r.week_start} x={xx(i)} y={h-8}
       fill="#95a2b5" textAnchor="middle" fontSize={width<390?8:9}>
       {week(r.week_start)}
      </text>:null)}
    {MODULES.filter(s=>selected.includes(s.key)).map(s=><g key={s.key}>
     <polyline fill="none" stroke={s.color} strokeWidth={expanded?2.9:2.3}
      strokeLinejoin="round" strokeLinecap="round"
      points={rows.map((r,i)=>xx(i)+","+yy(r[s.key])).join(" ")}
      pointerEvents="none"/>
     {rows.map((r,i)=><g role="button" tabIndex={0} key={r.week_start}
      aria-label={day(r.week_start)+": "+nf.format(r[s.key])+" "+s.label+
       " users. Open drill-down."+(r.limited_tracking?" Limited tracking coverage.":"")}
      onClick={e=>open(r,s.key,e.currentTarget)}
      onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){
       e.preventDefault();open(r,s.key,e.currentTarget);
      }}}
      onMouseEnter={e=>showTooltip(r,e.currentTarget)}
      onFocus={e=>showTooltip(r,e.currentTarget)}
      onMouseLeave={()=>setHovered(null)}
      onBlur={()=>setHovered(null)}
      className="po-workflow-plot-point">
      <circle className="po-workflow-halo" cx={xx(i)} cy={yy(r[s.key])} r={expanded?19:16}/>
      <circle className="po-workflow-point-marker" cx={xx(i)} cy={yy(r[s.key])} r={expanded?5:3.5}
       fill="white" stroke={s.color} strokeWidth={2}/>
     </g>)}
    </g>)}
   </svg>
   {hovered&&hoveredRow?<div role="tooltip"
    className={"po-workflow-tooltip"+(hovered.below?" is-below":"")}
    style={{
     left:hovered.left,
     top:hovered.top,
     "--po-workflow-tooltip-pointer":hovered.pointer+"px",
    } as CSSProperties}>
    <strong className="po-workflow-tooltip-heading">{day(hoveredRow.week_start)}</strong>
    <div className="po-workflow-tooltip-rows">
     {MODULES.map(m=><div className="po-workflow-tooltip-row" key={m.key}>
      <span className="po-workflow-tooltip-label">
       <i style={{background:m.color}}/>{m.label}
      </span>
      <strong>{nf.format(hoveredRow[m.key])}</strong>
     </div>)}
    </div>
    {hoveredRow.limited_tracking?<small>Tracking incomplete for this week</small>:null}
   </div>:null}
   </div>}
 </div>;
}

function ModuleMix({
 data,ready,onMask,expanded=false,
}:{
 data:WorkflowSummary|null;ready:boolean;
 onMask:(mask:WorkflowMask,label:string,trigger:HTMLElement)=>void;
 expanded?:boolean;
}){
 if(!data||!ready)return <Unavailable/>;
 const mix=data.mix;
 const multiPct=percentage(mix.current_multi,mix.current_total);
 const previousPct=percentage(mix.previous_multi,mix.previous_total);
 const delta=multiPct-previousPct;
 const ranked=COMBINATIONS.map(category=>({
  ...category,item:mix.rows.find(row=>row.mask===category.mask)!,
 })).filter(category=>category.item.current>0||category.item.previous>0)
  .sort((a,b)=>b.item.current-a.item.current
    ||b.item.previous-a.item.previous);
 const maxShare=Math.max(0,...ranked.flatMap(c=>[
  percentage(c.item.current,mix.current_total),
  percentage(c.item.previous,mix.previous_total),
 ]));
 // A shared scale is essential: neither period should get its own bar axis.
 const maxAxis=Math.max(40,Math.ceil(maxShare/40)*40);
 const ticks=Array.from({length:5},(_,i)=>maxAxis*i/4);
 return <div className={"po-native-module-mix"+(expanded?" is-expanded":"")}>
  <div className="po-mix-summary">
   <strong>{multiPct.toFixed(1)}%</strong>
   <span>use more than one module</span>
   <small>{delta>0?"+":""}{delta.toFixed(1)} pp vs previous 28 days</small>
  </div>
   <div className="po-mix-dumbbell" role="group"
    aria-label="Current versus previous share of core-active companies, by combination">
    <div className="po-mix-dumbbell-legend" aria-hidden="true">
     <span><i className="po-mix-current-dot"/> Current 28d</span>
     <span><i className="po-mix-prior-dot"/> Previous 28d</span>
     <small>Click a row to view companies</small>
    </div>
    <div className="po-mix-dumbbell-head" aria-hidden="true">
     <span>Combination</span>
     <span className="po-mix-dumbbell-ticks">
      {ticks.map((n,i)=><span key={i}
       style={{left:i*25+"%"}}>{n.toFixed(0)}%</span>)}
     </span>
     <span>Now</span><span>Δ pp</span>
    </div>
    <div className="po-mix-dumbbell-rows">
     {ranked.map(category=>{
      const item=category.item;
      const now=percentage(item.current,mix.current_total);
      const prior=percentage(item.previous,mix.previous_total);
      const diff=now-prior;
      const nowX=now/maxAxis*100;
      const prevX=prior/maxAxis*100;
      const trackLeft=Math.min(nowX,prevX);
      const trackWidth=Math.abs(nowX-prevX);
      const direction=diff>0.05?"up":diff<-.05?"down":"flat";
      return <button key={category.mask} type="button"
       className={"po-mix-dumbbell-row is-"+direction}
       onClick={e=>onMask(category.mask,category.label,e.currentTarget)}
       aria-label={category.label+": Current "+item.current+" of "+
        mix.current_total+" companies, "+now.toFixed(1)+" percent. Previous "+
        item.previous+" of "+mix.previous_total+" companies, "+
        prior.toFixed(1)+" percent. "+
        (diff>0?"+":"")+diff.toFixed(1)+" percentage points. Open company breakdown."}>
       <span className="po-mix-dumbbell-name">{category.label}</span>
       <span className="po-mix-dumbbell-plot" aria-hidden="true">
        <i className="po-mix-dumbbell-connector" style={{
         left:trackLeft+"%",width:Math.max(trackWidth,.15)+"%",
        }}/>
        <i className="po-mix-dumbbell-prior" style={{left:prevX+"%"}}/>
        <i className="po-mix-dumbbell-current" style={{left:nowX+"%"}}/>
       </span>
       <strong className="po-mix-dumbbell-value">{now.toFixed(1)}%</strong>
       <span className="po-mix-dumbbell-delta">
        {diff>0?"+":""}{diff.toFixed(1)}
       </span>
       <span className="po-mix-dumbbell-tooltip" aria-hidden="true">
        <strong>{category.label}</strong>
        <span>Current <b>{item.current} companies · {now.toFixed(1)}%</b></span>
        <span>Previous <b>{item.previous} companies · {prior.toFixed(1)}%</b></span>
       </span>
      </button>;
     })}
    </div>
   </div>
 </div>;
}

type ExpandedKind="feature"|"mix";
function WorkflowExpanded({
 kind,data,ready,view,selected,onSelect,onView,onPoint,onMask,onClose,drillOpen,
}:{
 kind:ExpandedKind;data:WorkflowSummary|null;ready:boolean;
 view:"chart"|"table";selected:WorkflowModule[];
 onSelect:(module:WorkflowModule)=>void;onView:()=>void;
 onPoint:(v:{week:string;module:WorkflowModule;count:number},t:HTMLElement|SVGElement)=>void;
 onMask:(mask:WorkflowMask,label:string,t:HTMLElement)=>void;
 onClose:()=>void;drillOpen:boolean;
}){
 const close=useRef<HTMLButtonElement>(null);
 useEffect(()=>{
  const old=document.body.style.overflow;document.body.style.overflow="hidden";
  close.current?.focus({preventScroll:true});
  return ()=>{document.body.style.overflow=old};
 },[]);
 useEffect(()=>{
  const escape=(e:KeyboardEvent)=>{
   if(e.key==="Escape"&&!drillOpen){
    e.preventDefault();e.stopImmediatePropagation();onClose();
   }
  };
  window.addEventListener("keydown",escape,true);
  return ()=>window.removeEventListener("keydown",escape,true);
 },[drillOpen,onClose]);
 const isTrend=kind==="feature";
 return <div className="po-native-expanded-overlay" role="presentation"
  onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}>
  <section className="po-report-expanded po-native-expanded-report po-workflow-expanded"
   role="dialog" aria-modal="true" aria-labelledby="po-workflow-expanded-title">
   <div className="report-modal-chrome">
    <span id="po-workflow-expanded-title">
     {isTrend?"Module usage over time":"Module combinations"} · Expanded view
    </span>
    <button ref={close} type="button" className="close-button" onClick={onClose}
     aria-label="Close expanded workflow report">
     <svg className="icon" aria-hidden="true"><use href="#i-close"/></svg>
    </button>
   </div>
   <div className="po-expanded-mount">
    <article className="po-report">
     <header className="po-report-head">
      <div>
       <h2>{isTrend?"Module usage over time":"Module combinations"}</h2>
       <p className="po-subtitle">
        {isTrend?"Distinct core-active users by module · 12 completed weeks":
         "Core-active companies · Last 28 days vs previous 28 days"}
       </p>
      </div>
     </header>
     <div className="po-body">
      {isTrend?<ModuleTrend data={data} ready={ready} selected={selected}
       onSelect={onSelect} view={view} onView={onView} onPoint={onPoint} expanded/>
       :<ModuleMix data={data} ready={ready} onMask={onMask} expanded/>}
     </div>
    </article>
   </div>
  </section>
 </div>;
}

export default function OverviewWorkflow({
 summary,usageSnapshot,trendTarget,mixTarget,
}:{
 summary:WorkflowSummary|null;usageSnapshot:OverviewUsageSnapshot|null;
 trendTarget:HTMLElement;mixTarget:HTMLElement;
}){
 const [asOfDate,setAsOfDate]=useState(usageSnapshot?.asOfDate??"");
 const [selected,setSelected]=useState<WorkflowModule[]>(["ap","ar","transactions"]);
 const [trendView,setTrendView]=useState<"chart"|"table">("chart");
 const [expanded,setExpanded]=useState<ExpandedKind|null>(null);
 const [trendDrill,setTrendDrill]=useState<{
  week:string;module:WorkflowModule;count:number;
 }|null>(null);
 const [mixDrill,setMixDrill]=useState<{
  mask:WorkflowMask;label:string;
 }|null>(null);
 const opener=useRef<HTMLElement|SVGElement|null>(null);
 const expandOpener=useRef<HTMLButtonElement|null>(null);
 useEffect(()=>{
  const onDate=(event:Event)=>{
   const v=(event as CustomEvent<{asOf:string}>).detail?.asOf;
   if(typeof v==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(v))setAsOfDate(v);
  };
  window.addEventListener("aia:overview-asof",onDate);
  return ()=>window.removeEventListener("aia:overview-asof",onDate);
 },[]);
 const ready=Boolean(summary&&usageSnapshot
  &&summary.snapshotId===usageSnapshot.snapshotId
  &&Date.parse(summary.asOf)===Date.parse(usageSnapshot.asOf)
  &&asOfDate===usageSnapshot.asOfDate);
 function changeSeries(k:WorkflowModule){
  setSelected(old=>old.includes(k)
   ?old.length>1?old.filter(x=>x!==k):old
   :[...old,k]);
 }
 const toggleTrend=()=>setTrendView(v=>v==="chart"?"table":"chart");
 useEffect(()=>{
  const cap=document.getElementById("po-feature-caption");
  const mix=document.getElementById("po-mix-caption");
  if(cap)cap.textContent=ready&&summary
   ?"Distinct core-active users · "+summary.weekly.length+" completed weeks"
   :"No verified module usage for this reporting date";
  if(mix)mix.textContent=ready&&summary
   ?"Core-active companies · "+dateTime(summary.mix.current_start)+
    " to "+dateTime(summary.mix.current_end)
   :"No verified module mix for this reporting date";
 },[ready,summary]);
 useEffect(()=>{
  const handlers:Array<{
   el:HTMLElement;fn:(e:MouseEvent)=>void;
  }>=[];
  function listen(selector:string,fn:(e:MouseEvent)=>void){
   const el=document.querySelector<HTMLElement>(selector);
   if(!el)return;
   const cb=(e:MouseEvent)=>{
    e.preventDefault();e.stopImmediatePropagation();fn(e);
   };
   el.addEventListener("click",cb,true);handlers.push({el,fn:cb});
  }
  listen('#po-feature-report [data-po-expand="po-feature-report"]',e=>{
   expandOpener.current=e.currentTarget as HTMLButtonElement;setExpanded("feature");
  });
  listen('#po-mix-report [data-po-expand="po-mix-report"]',e=>{
   expandOpener.current=e.currentTarget as HTMLButtonElement;setExpanded("mix");
  });
  listen('#po-feature-report [data-po-chart-view="feature"]',toggleTrend);
  return ()=>handlers.forEach(({el,fn})=>el.removeEventListener("click",fn,true));
 },[trendTarget,mixTarget]);
 useEffect(()=>{
  const a=document.querySelector<HTMLButtonElement>('#po-feature-report [data-po-chart-view="feature"]');
  if(a)a.textContent=trendView==="chart"?"View table":"View chart";
 },[trendView]);
 function point(v:{week:string;module:WorkflowModule;count:number},t:HTMLElement|SVGElement){
  if(!ready)return;
  opener.current=t;setTrendDrill(v);
 }
 function maskClick(mask:WorkflowMask,label:string,t:HTMLElement){
  if(!ready)return;
  opener.current=t;setMixDrill({mask,label});
 }
 function closeDrill(){
  setTrendDrill(null);setMixDrill(null);
  requestAnimationFrame(()=>opener.current?.focus({preventScroll:true}));
 }
 function closeExpanded(){
  setExpanded(null);
  requestAnimationFrame(()=>expandOpener.current?.focus({preventScroll:true}));
 }
 return <>
  {createPortal(<ModuleTrend data={summary} ready={ready}
   selected={selected} onSelect={changeSeries} view={trendView}
   onView={toggleTrend} onPoint={point}/>,trendTarget)}
  {createPortal(<ModuleMix data={summary} ready={ready}
   onMask={maskClick}/>,mixTarget)}
  {expanded&&typeof document!=="undefined"?
   createPortal(<WorkflowExpanded kind={expanded} data={summary} ready={ready}
    selected={selected} onSelect={changeSeries}
    view={trendView}
    onView={toggleTrend}
    onPoint={point} onMask={maskClick} onClose={closeExpanded}
    drillOpen={!!trendDrill||!!mixDrill}/>,document.body):null}
  {trendDrill&&summary&&typeof document!=="undefined"?
   createPortal(<WorkflowModuleUsersModal key={trendDrill.week+":"+trendDrill.module}
    summary={summary} week={trendDrill.week} module={trendDrill.module}
    expected={trendDrill.count} onClose={closeDrill}/>,document.body):null}
  {mixDrill&&summary&&typeof document!=="undefined"?
   createPortal(<WorkflowMixCompaniesModal key={mixDrill.mask} summary={summary}
    mask={mixDrill.mask} label={mixDrill.label} onClose={closeDrill}/>,document.body):null}
 </>;
}
