"use client";

import { useEffect, useRef, useState, type RefObject } from "react";
import { createPortal } from "react-dom";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type { OverviewActiveCharts, ActiveWeeklyRow } from "../../lib/overview/active-charts";
import OverviewActiveChartModal, { type ChartDrillTarget } from "./overview-active-chart-modal";

const nf = new Intl.NumberFormat("en-US");
const dateFmt = new Intl.DateTimeFormat("en-GB", {
  timeZone:"UTC",day:"numeric",month:"short",
});
function weekLabel(value: string) {
  return dateFmt.format(new Date(value+"T12:00:00Z"));
}
function weekEnd(value: string) {
  return dateFmt.format(new Date(Date.parse(value+"T12:00:00Z")+6*86_400_000));
}
function labelDate(value: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone:"UTC",day:"numeric",month:"short",year:"numeric",
  }).format(new Date(value+"T12:00:00Z"));
}
function useChartWidth(ref: RefObject<HTMLDivElement | null>) {
  const [width,setWidth] = useState(560);
  useEffect(()=>{
    const element=ref.current;
    if(!element)return;
    const measure=()=>setWidth(Math.max(300,Math.round(element.clientWidth||560)));
    measure();
    const observer=typeof ResizeObserver!=="undefined"?new ResizeObserver(measure):null;
    observer?.observe(element);
    window.addEventListener("resize",measure);
    return ()=>{observer?.disconnect();window.removeEventListener("resize",measure)};
  },[ref]);
  return width;
}
function Unavailable({ reason }: { reason: string }) {
  return <div className="po-chart-live-empty" role="status">
    <strong>Chart data unavailable</strong>
    <span>{reason}</span>
  </div>;
}

function WeeklyChart({
  chart,ready,onDrill,expanded=false,
}: {
  chart: OverviewActiveCharts|null;
  ready: boolean;
  expanded?: boolean;
  onDrill: (target:ChartDrillTarget,button:HTMLElement|SVGElement)=>void;
}) {
  const [view,setView]=useState<"chart"|"table">("chart");
  const [hover,setHover]=useState<string|null>(null);
  const wrap=useRef<HTMLDivElement>(null);
  const width=useChartWidth(wrap);
  if(!ready||!chart) return <Unavailable reason="No matching published snapshot for the selected reporting date."/>;
  const rows=chart.weekly.rows;
  if(!rows.length)return <Unavailable reason="No completed weeks in the selected reporting range."/>;
  const height=expanded?450:235,left=31,right=10,top=22,bottom=28;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(50,Math.ceil(Math.max(...rows.map(x=>x.users))*1.08/50)*50);
  const step=plotW/rows.length;
  const bw=Math.max(7,Math.min(29,step*0.6));
  const last=rows[rows.length-1];
  function open(row:ActiveWeeklyRow,button:HTMLElement|SVGElement){
    onDrill({
      kind:"weekly",key:row.week_start,label:weekLabel(row.week_start)+"–"+weekEnd(row.week_start),
      windowLabel:labelDate(row.week_start)+" to "+weekEnd(row.week_start),
      firstSegment:"all",
      expected:{all:row.users,returning:row.returning,first_observed:row.first_observed},
      limitedTracking:row.limited_tracking,
    },button);
  }
  return <div ref={wrap} className="po-native-weekly-chart">
    <div className="po-legend">
      <span><i className="po-dot"/>Returning</span>
      <span><i className="po-dot light"/>First observed</span>
      <button className="po-active-chart-view-toggle" type="button" onClick={()=>setView(v=>v==="chart"?"table":"chart")}>
        {view==="chart"?"View table":"View chart"}
      </button>
    </div>
    {view==="table"?
      <div className="po-data-view po-live-weekly-table">
        <table className="po-data-table">
          <thead><tr><th>Week starting</th><th>Returning</th>
            <th>First observed</th><th>Total users</th></tr></thead>
          <tbody>{rows.map(row=><tr key={row.week_start}>
            <td><button className="po-cell-link" type="button"
              onClick={e=>open(row,e.currentTarget)}>
              {labelDate(row.week_start)}{row.limited_tracking?" *":""}
            </button></td>
            <td>{nf.format(row.returning)}</td>
            <td>{nf.format(row.first_observed)}</td>
            <td><button className="po-cell-link" type="button"
              onClick={e=>open(row,e.currentTarget)}><strong>{nf.format(row.users)}</strong></button></td>
          </tr>)}</tbody>
        </table>
      </div>
    :<>
      <svg className="po-chart" viewBox={"0 0 "+width+" "+height}
        aria-label="Weekly unique independent core-work users, returning and first observed" role="group">
        {Array.from({length:5},(_,index)=>{
          const value=max*index/4,y=top+plotH*(1-value/max);
          return <g key={index}>
            <line x1={left} y1={y} x2={width-right} y2={y}
              stroke={index===0?"#dfe5ef":"#ecf0f6"}
              strokeDasharray={index===0?undefined:"2 5"}/>
            <text x={left-9} y={y+3} textAnchor="end" fill="#9aa7b9" fontSize={9}>
              {Math.round(value)}
            </text>
          </g>;
        })}
        {rows.map((row,index)=>{
          const x=left+step*index+step/2-bw/2;
          const retH=row.returning/max*plotH;
          const firstH=row.first_observed/max*plotH;
          const yR=top+plotH-retH;
          const yF=yR-firstH;
          return <g key={row.week_start} role="button" tabIndex={0}
            aria-label={labelDate(row.week_start)+": "+row.users+" users, "+row.returning+
              " returning, "+row.first_observed+" first observed."+
              (row.limited_tracking?" Activity tracking incomplete.":"")}
            onClick={e=>open(row,e.currentTarget)}
            onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();open(row,e.currentTarget)}}}
            onMouseEnter={()=>setHover(row.week_start)}
            onMouseLeave={()=>setHover(null)}
            onFocus={()=>setHover(row.week_start)}
            onBlur={()=>setHover(null)}
            className="po-weekly-live-bar">
            <title>{labelDate(row.week_start)}: {row.users} active · {row.returning} returning · {row.first_observed} first observed{row.limited_tracking?" · Tracking incomplete":""}</title>
            <rect className="po-bar-hit" x={x-6} y={top-5} width={bw+12} height={plotH+5} rx={3}/>
            <rect x={x} y={yR} width={bw} height={retH} fill="#315de5" />
            <rect x={x} y={yF} width={bw} height={firstH} fill="#b9d0fc" />
            <text x={x+bw/2} y={yF-7} textAnchor="middle" fontSize={width<440?8:9} fill="#7b8daa">
              {row.users}
            </text>
            {row.limited_tracking?<text x={x+bw-1} y={yF-8} fontSize={11}
              fill="#b27840" fontWeight={700}>*</text>:null}
            {(width>500||index%2===0||row.week_start===last.week_start)?
              <text x={x+bw/2} y={height-8} textAnchor="middle" fontSize={width<390?8:9} fill="#95a2b5">
                {weekLabel(row.week_start)}
              </text>:null}
          </g>;
        })}
      </svg>
      {hover?<div className="po-weekly-hover" role="status">
        {(()=>{
          const row=rows.find(x=>x.week_start===hover);
          if(!row)return null;
          return <><strong>{labelDate(row.week_start)}</strong>
            <span>{row.returning} returning · {row.first_observed} first observed</span>
            {row.limited_tracking?<small>Limited tracking coverage</small>:null}
          </>;
        })()}
      </div>:null}
    </>}
  </div>;
}

function FrequencyChart({
  chart,ready,onDrill,
}: {
  chart: OverviewActiveCharts|null;
  ready:boolean;
  onDrill:(target:ChartDrillTarget,button:HTMLElement|SVGElement)=>void;
}) {
  if(!ready||!chart) return <Unavailable reason="No matching published snapshot for the selected reporting date."/>;
  const data=chart.frequency;
  const first=data.rows[0];
  return <div className="po-native-frequency-chart">
    <div className="po-insight">
      <strong>{first.share_pct.toFixed(1)}%</strong>
      <span>were active in <b>only one</b> of the<br/>last four completed weeks</span>
    </div>
    <div className="po-frequency">
      {data.rows.map(row=><button className="po-freq-row po-live-frequency-row"
        type="button" key={row.active_weeks}
        aria-label={"Exactly "+row.active_weeks+" weeks: "+row.users+
          " users, "+row.share_pct.toFixed(1)+" percent. Open users."}
        onClick={event=>onDrill({
          kind:"frequency",
          key:String(row.active_weeks),
          label:"Exactly "+row.active_weeks+" "+(row.active_weeks===1?"week":"weeks"),
          windowLabel:labelDate(data.window_start)+" to "+
            labelDate(new Date(Date.parse(data.window_end+"T12:00:00Z")-86_400_000).toISOString().slice(0,10)),
          firstSegment:"all",
          expected:{all:row.users,returning:0,first_observed:0},
        },event.currentTarget)}>
        <span>Exactly {row.active_weeks} {row.active_weeks===1?"week":"weeks"}</span>
        <span className="po-bar-track"><i style={{width:(data.total_users?row.users*100/data.total_users:0)+"%"}}/></span>
        <strong>{nf.format(row.users)}</strong>
        <span>{row.share_pct.toFixed(1)}%</span>
      </button>)}
    </div>
    <p className="po-active-chart-note">Each user belongs to one bucket · Four complete Monday–Sunday weeks.</p>
  </div>;
}


type ExpandedReportKind = "weekly" | "frequency";

/**
 * The prototype's move-the-article expansion is incompatible with React portals.
 * Render the same approved report inside a native React overlay instead.
 * Existing user/company drill overlays (z-index 500/700) remain usable above it.
 */
function ExpandedActiveReport({
  kind, chart, ready, onDrill, onClose, drillOpen,
}: {
  kind: ExpandedReportKind;
  chart: OverviewActiveCharts|null;
  ready: boolean;
  onDrill: (target:ChartDrillTarget,button:HTMLElement|SVGElement)=>void;
  onClose: ()=>void;
  drillOpen: boolean;
}) {
  const closeButton=useRef<HTMLButtonElement>(null);
  const panel=useRef<HTMLElement>(null);
  const weekly=kind==="weekly";

  useEffect(()=>{
    const oldOverflow=document.body.style.overflow;
    document.body.style.overflow="hidden";
    closeButton.current?.focus({preventScroll:true});
    return ()=>{document.body.style.overflow=oldOverflow};
  },[]);

  useEffect(()=>{
    const onKey=(event:KeyboardEvent)=>{
      if(drillOpen || document.querySelector(".po-overview-info-dialog[open]"))return;
      if(event.key==="Escape"){
        event.preventDefault();
        event.stopImmediatePropagation();
        onClose();
        return;
      }
      if(event.key!=="Tab")return;
      const focusables=panel.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]),a[href],[tabindex="0"]'
      );
      if(!focusables?.length)return;
      const first=focusables[0],last=focusables[focusables.length-1];
      if(event.shiftKey&&document.activeElement===first){
        event.preventDefault();last.focus();
      }else if(!event.shiftKey&&document.activeElement===last){
        event.preventDefault();first.focus();
      }
    };
    window.addEventListener("keydown",onKey,true);
    return ()=>window.removeEventListener("keydown",onKey,true);
  },[drillOpen,onClose]);

  const rows=chart?.weekly.rows;
  const range=weekly
    ? rows?.length
      ? labelDate(rows[0].week_start)+" to "+weekEnd(rows[rows.length-1].week_start)
      : "No completed weeks"
    : chart
      ? labelDate(chart.frequency.window_start)+" to "+
        labelDate(new Date(Date.parse(chart.frequency.window_end+"T12:00:00Z")-
          86_400_000).toISOString().slice(0,10))
      : "No complete reporting window";

  return <div className="po-native-expanded-overlay" role="presentation"
    onMouseDown={event=>{
      if(event.target===event.currentTarget)onClose();
    }}>
    <section ref={panel} className="po-report-expanded po-native-expanded-report"
      role="dialog" aria-modal="true" aria-labelledby="po-native-expanded-title">
      <div className="report-modal-chrome">
        <span id="po-native-expanded-title">
          {weekly?"Weekly core-active users":"Core usage frequency"} · Expanded view
        </span>
        <div className="po-expanded-head-actions">
          <button type="button" className="icon-button"
            data-po-help={weekly?"weekly":"frequency"}
            aria-label="How this chart is counted" title="How it's counted">
            <svg className="icon" aria-hidden="true"><use href="#i-info"/></svg>
          </button>
          <button ref={closeButton} type="button" className="close-button"
            onClick={onClose} aria-label="Close expanded report">
            <svg className="icon" aria-hidden="true"><use href="#i-close"/></svg>
          </button>
        </div>
      </div>
      <div className="po-expanded-mount">
        <article className="po-report">
          <header className="po-report-head">
            <div>
              <h2>{weekly?"Weekly core-active users":"Core usage frequency"}</h2>
              <p className="po-subtitle">
                {weekly?"12 completed weeks · ":""}
                {range}
                {!weekly&&chart?" · "+nf.format(chart.frequency.total_users)+" users":""}
              </p>
            </div>
          </header>
          <div className="po-body">
            {weekly
              ? <WeeklyChart chart={chart} ready={ready} onDrill={onDrill} expanded/>
              : <FrequencyChart chart={chart} ready={ready} onDrill={onDrill}/>}
          </div>
          {weekly?<footer className="po-chart-footer">
            <span className="po-foot-label">
              Distinct users per week, not activity count
            </span>
          </footer>:null}
        </article>
      </div>
    </section>
  </div>;
}

export default function OverviewActiveUsage({
  snapshot,charts,weeklyTarget,frequencyTarget,
}: {
  snapshot:OverviewUsageSnapshot|null;
  charts:OverviewActiveCharts|null;
  weeklyTarget:HTMLElement;
  frequencyTarget:HTMLElement;
}) {
  const [asOfDate,setAsOfDate]=useState(snapshot?.asOfDate??"");
  const [drill,setDrill]=useState<ChartDrillTarget|null>(null);
  const [expanded,setExpanded]=useState<ExpandedReportKind|null>(null);
  const opener=useRef<HTMLElement|SVGElement|null>(null);
  const expandOpener=useRef<HTMLButtonElement|null>(null);
  useEffect(()=>{
    const onDate=(event:Event)=>{
      const value=(event as CustomEvent<{asOf:string}>).detail?.asOf;
      if(typeof value==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(value))setAsOfDate(value);
    };
    window.addEventListener("aia:overview-asof",onDate);
    return ()=>window.removeEventListener("aia:overview-asof",onDate);
  },[]);

  // Capture the existing header buttons before the legacy document click handler
  // attempts to move a React-controlled report into the prototype dialog.
  useEffect(()=>{
    const defs: Array<{selector:string;kind:ExpandedReportKind}>= [
      {selector:'#po-weekly-report [data-po-expand="po-weekly-report"]',kind:"weekly"},
      {selector:'#po-frequency-report [data-po-expand="po-frequency-report"]',kind:"frequency"},
    ];
    const registrations: Array<{button:HTMLButtonElement;listener:(event:MouseEvent)=>void}>=[];
    for(const def of defs){
      const button=document.querySelector<HTMLButtonElement>(def.selector);
      if(!button)continue;
      const listener=(event:MouseEvent)=>{
        event.preventDefault();
        event.stopImmediatePropagation();
        expandOpener.current=button;
        setExpanded(def.kind);
      };
      button.addEventListener("click",listener,true);
      registrations.push({button,listener});
    }
    return ()=>registrations.forEach(({button,listener})=>
      button.removeEventListener("click",listener,true));
  },[weeklyTarget,frequencyTarget]);
  const ready=Boolean(snapshot&&charts
    && charts.snapshotId===snapshot.snapshotId
    && Date.parse(charts.asOf)===Date.parse(snapshot.asOf)
    && asOfDate===snapshot.asOfDate);
  useEffect(()=>{
    const weekly=document.getElementById("po-weekly-caption");
    const frequency=document.getElementById("po-frequency-caption");
    if(weekly)weekly.textContent=ready&&charts&&charts.weekly.rows.length
      ? charts.weekly.rows.length+" completed weeks · "+
        labelDate(charts.weekly.rows[0].week_start)+" to "+
        weekEnd(charts.weekly.rows[charts.weekly.rows.length-1].week_start)
      : ready ? "No completed weeks in selected reporting range" :
        "Live data unavailable for this reporting date";
    if(frequency)frequency.textContent=ready&&charts
      ? labelDate(charts.frequency.window_start)+" – "+
        labelDate(new Date(Date.parse(charts.frequency.window_end+"T12:00:00Z")-86_400_000).toISOString().slice(0,10))+
        " · "+nf.format(charts.frequency.total_users)+" users"
      : "Live data unavailable for this reporting date";
  },[ready,charts]);
  function open(target:ChartDrillTarget,button:HTMLElement|SVGElement){
    if(!ready)return;
    opener.current=button;
    setDrill(target);
  }
  function close(){
    setDrill(null);
    requestAnimationFrame(()=>opener.current?.focus({preventScroll:true}));
  }
  function closeExpanded(){
    setExpanded(null);
    requestAnimationFrame(()=>expandOpener.current?.focus({preventScroll:true}));
  }
  return <>
    {createPortal(<WeeklyChart chart={charts} ready={ready} onDrill={open}/>,weeklyTarget)}
    {createPortal(<FrequencyChart chart={charts} ready={ready} onDrill={open}/>,frequencyTarget)}

    {expanded&&typeof document!=="undefined"?createPortal(
      <ExpandedActiveReport kind={expanded} chart={charts} ready={ready}
        onDrill={open} onClose={closeExpanded} drillOpen={drill!==null}/>,
      document.body):null}
    {drill&&snapshot&&typeof document!=="undefined"?
      createPortal(<OverviewActiveChartModal key={drill.kind+":"+drill.key}
        target={drill} snapshot={snapshot} onClose={close}/>,document.body):null}
  </>;
}
