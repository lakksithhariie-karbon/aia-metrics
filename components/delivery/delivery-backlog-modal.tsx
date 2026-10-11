"use client";

import { useEffect, useRef, useState } from "react";
import type { DeliveryDashboard } from "../../lib/delivery/types";

type BacklogWeek=DeliveryDashboard["flow"]["backlog_trend"][number];
const nf=new Intl.NumberFormat("en-IN");
const fmt=(value:number)=>nf.format(value);
const signed=(value:number)=>(value>0?"+":"")+fmt(value);
const date=(value:string)=>{
  const d=new Date(value);
  return Number.isNaN(d.getTime())?"—":new Intl.DateTimeFormat("en-GB",{
    day:"2-digit",month:"short",year:"numeric",timeZone:"Asia/Kolkata",
  }).format(d);
};
const limit=10;

export default function DeliveryBacklogModal({rows,weekStart,onClose}:{
  rows:BacklogWeek[];weekStart:string;onClose:()=>void;
}){
  const sorted=[...rows].filter(row=>
    Number.isFinite(row.open_eod)&&Number.isFinite(row.created)&&
    Number.isFinite(row.resolved)&&Number.isFinite(row.net_movement))
    .sort((a,b)=>b.week_start.localeCompare(a.week_start)).slice(0,20);
  const [selected,setSelected]=useState(weekStart);
  const [descending,setDescending]=useState(true);
  const [page,setPage]=useState(()=>Math.floor(
    Math.max(0,sorted.findIndex(row=>row.week_start===weekStart))/limit)+1);
  const close=useRef<HTMLButtonElement>(null);
  const ordered=descending?sorted:[...sorted].reverse();
  const totalPages=Math.max(1,Math.ceil(ordered.length/limit));
  const visible=ordered.slice((page-1)*limit,page*limit);
  const active=sorted.find(row=>row.week_start===selected)??sorted[0];
  useEffect(()=>{
    close.current?.focus({preventScroll:true});
    const onKey=(event:KeyboardEvent)=>{
      if(event.key==="Escape"){event.preventDefault();onClose();}
    };
    document.addEventListener("keydown",onKey);
    return ()=>document.removeEventListener("keydown",onKey);
  },[onClose]);
  return <div className="ed-overlay" role="presentation"
    onMouseDown={event=>{if(event.target===event.currentTarget)onClose();}}>
    <section className="rd-modal rd-activation-modal ed-investigation-modal ed-backlog-modal"
      role="dialog" aria-modal="true" aria-labelledby="ed-backlog-title"
      onKeyDown={event=>{
        if(event.key!=="Tab")return;
        const targets=Array.from(event.currentTarget.querySelectorAll<HTMLElement>(
          'button:not([disabled]),a[href]'
        ));
        if(!targets.length)return;
        if(event.shiftKey&&document.activeElement===targets[0]){
          event.preventDefault();targets[targets.length-1].focus();
        } else if(!event.shiftKey&&document.activeElement===targets[targets.length-1]){
          event.preventDefault();targets[0].focus();
        }
      }}>
      <header className="rd-modal-head ed-investigation-head">
        <div>
          <p>Backlog investigation</p>
          <h2 id="ed-backlog-title">Week of {date(active?.week_start??weekStart)}</h2>
          <span>{active?fmt(active.open_eod)+" open bugs at week end":"No reported weeks"}</span>
        </div>
        <button type="button" ref={close} className="rd-close ed-investigation-close"
          aria-label="Close backlog investigation" onClick={onClose}>×</button>
      </header>
      <nav className="ed-backlog-tabs" aria-label="Backlog investigation views">
        <button type="button" className="ed-backlog-tab" aria-current="page">Weekly breakdown</button>
        <button type="button" className="ed-backlog-tab" disabled
          title="Historical issue-level evidence has not been published">Created bugs</button>
        <button type="button" className="ed-backlog-tab" disabled
          title="Historical issue-level evidence has not been published">Resolved bugs</button>
      </nav>
      {active?<div className="ed-backlog-context">
        <span>Opening <strong>{fmt(active.open_eod-active.net_movement)}</strong></span>
        <span>Created <strong>{fmt(active.created)}</strong></span>
        <span>Resolved <strong>{fmt(active.resolved)}</strong></span>
        <span>Net <strong>{signed(active.net_movement)}</strong></span>
        <span>Closing <strong>{fmt(active.open_eod)}</strong></span>
      </div>:null}
      <div className="rd-table-wrap ed-investigation-table-wrap" role="region"
        aria-label="Published weekly Jira bug backlog totals" tabIndex={0}>
        <table className="rd-activation-table ed-investigation-table ed-backlog-table">
          <thead><tr>
            <th scope="col"><button type="button" className="ed-investigation-sort"
              onClick={()=>{
                setDescending(value=>!value);
                setPage(1);
              }}>Week <span aria-hidden="true">{descending?"↓":"↑"}</span></button></th>
            <th scope="col">Opening</th><th scope="col">Created</th>
            <th scope="col">Resolved</th><th scope="col">Net</th><th scope="col">Closing</th>
          </tr></thead>
          <tbody>{visible.map(row=><tr key={row.week_start}
            className={"ed-investigation-row"+(row.week_start===selected?" ed-backlog-selected":"")}>
            <td><button type="button" className="ed-backlog-week-button"
              aria-pressed={row.week_start===selected}
              onClick={()=>setSelected(row.week_start)}>{date(row.week_start)}</button></td>
            <td>{fmt(row.open_eod-row.net_movement)}</td>
            <td>{fmt(row.created)}</td><td>{fmt(row.resolved)}</td>
            <td className={row.net_movement>0?"ed-backlog-net-positive":"ed-backlog-net-negative"}>
              {signed(row.net_movement)}</td>
            <td><strong>{fmt(row.open_eod)}</strong></td>
          </tr>)}</tbody>
        </table>
      </div>
      <p className="ed-backlog-scope-note">
        These are published weekly bug totals. Historical issue-level lists are unavailable,
        so no current issue records are presented as historical evidence.
      </p>
      {totalPages>1?<footer className="rd-modal-foot rd-modal-foot-paginated ed-investigation-foot">
        <nav className="rd-pagination" aria-label="Backlog weeks">
          <button type="button" disabled={page===1} aria-label="Previous page"
            onClick={()=>setPage(value=>value-1)}>‹</button>
          {Array.from({length:totalPages},(_,i)=>i+1).map(n=>
            <button type="button" key={n} aria-current={page===n?"page":undefined}
              onClick={()=>setPage(n)}>{n}</button>)}
          <button type="button" disabled={page===totalPages} aria-label="Next page"
            onClick={()=>setPage(value=>value+1)}>›</button>
        </nav>
      </footer>:null}
    </section>
  </div>;
}
