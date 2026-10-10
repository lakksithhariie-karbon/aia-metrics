"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type {
  DeliveryDashboard,DeliveryEvidence,DeliveryEvidenceItem,DeliveryEvidenceSort,DeliveryFilters,
} from "../../lib/delivery/types";
import DeliveryIssueDetailModal from "./delivery-issue-detail-modal";

type DrillTarget={key:string;label:string;sprintId:number|null};
const number=new Intl.NumberFormat("en-IN");
const show=(v:string|null|undefined)=>v?.trim()||"—";
const date=(value:string|null|undefined)=>{
  if(!value)return "—";
  const d=new Date(value);
  return Number.isNaN(d.getTime())?"—":new Intl.DateTimeFormat("en-GB",{
    day:"2-digit",month:"short",year:"numeric",timeZone:"Asia/Kolkata",
  }).format(d);
};
const duration=(hours:number|null|undefined)=>{
  if(hours==null||!Number.isFinite(hours))return "—";
  return hours>=48?(hours/24).toFixed(1)+"d":hours.toFixed(1)+"h";
};
const sorts:Array<{key:DeliveryEvidenceSort;label:string}>=[
  {key:"issue_key",label:"Key"},{key:"created_at",label:"Created"},
  {key:"resolved_at",label:"Resolved"},{key:"severity",label:"Sev"},
  {key:"status",label:"Status"},{key:"priority",label:"Priority"},
  {key:"assignee",label:"Assignee"},
];
const pages=(page:number,total:number):Array<number|"…">=>{
  if(total<=7)return Array.from({length:total},(_,i)=>i+1);
  const keep=new Set([1,total,page-1,page,page+1].filter(n=>n>=1&&n<=total));
  const list=Array.from(keep).sort((a,b)=>a-b);
  const result:Array<number|"…">=[];
  list.forEach((value,i)=>{
    if(i&&value-list[i-1]>1)result.push("…");
    result.push(value);
  });
  return result;
};

function EvidenceSkeleton({review}:{review:boolean}){
  return <table className="rd-activation-table ed-investigation-table ed-investigation-skeleton" aria-hidden="true">
    <thead><tr><th/><th>Key</th><th>Created</th><th>Resolved</th><th>Sev</th>
      <th>Status</th><th>Priority</th><th>Assignee</th>
      {review?<th>Review dwell</th>:null}</tr></thead>
    <tbody>{Array.from({length:10},(_,i)=><tr key={i}>
      <td><span className="ed-skeleton-line" style={{width:15}}/></td>
      {Array.from({length:review?8:7},(_,j)=><td key={j}>
        <span className="ed-skeleton-line" style={{width:(j===0?85:74-(i+j)%3*12)+"%"}}/>
      </td>)}
    </tr>)}</tbody>
  </table>;
}

export default function DeliveryEvidenceModal({target,data,filters,onClose}:{
  target:DrillTarget;data:DeliveryDashboard;filters:DeliveryFilters;onClose:()=>void;
}){
  const [query,setQuery]=useState("");
  const [search,setSearch]=useState("");
  const [sort,setSort]=useState<DeliveryEvidenceSort>("created_at");
  const [direction,setDirection]=useState<"asc"|"desc">("desc");
  const [page,setPage]=useState(1);
  const [expanded,setExpanded]=useState<string|null>(null);
  const [detailKey,setDetailKey]=useState<string|null>(null);
  const [value,setValue]=useState<DeliveryEvidence|null>(null);
  const [cohortTotal,setCohortTotal]=useState<number|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState(false);
  const [retry,setRetry]=useState(0);
  const [exporting,setExporting]=useState(false);
  const [exportError,setExportError]=useState<string|null>(null);
  const scroll=useRef<HTMLDivElement>(null);
  const closeRef=useRef<HTMLButtonElement>(null);
  const triggerRef=useRef<HTMLButtonElement|null>(null);
  const size=10;
  const scopedFilters=useMemo(()=>({...filters,sprint:target.sprintId??filters.sprint}),
    [filters.sprint,filters.module,filters.sub_module,filters.severity,filters.assignee,target.sprintId]);
  const pageCount=Math.max(1,Math.ceil((value?.total??0)/size));
  const pageStart=value?.total?((page-1)*size+1):0;
  const pageEnd=value?Math.min(page*size,value.total):0;

  useEffect(()=>{
    const id=setTimeout(()=>setSearch(query.trim()),260);
    return ()=>clearTimeout(id);
  },[query]);

  useEffect(()=>{
    closeRef.current?.focus({preventScroll:true});
    const onKey=(event:KeyboardEvent)=>{
      if(event.key==="Escape"&&!detailKey){event.preventDefault();onClose();}
    };
    document.addEventListener("keydown",onKey);
    return ()=>document.removeEventListener("keydown",onKey);
  },[onClose,detailKey]);

  useEffect(()=>{
    const controller=new AbortController();
    setLoading(true);setError(false);setValue(null);
    fetch("/api/delivery/evidence",{
      method:"POST",cache:"no-store",signal:controller.signal,
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({key:target.key,snapshot_id:data.snapshot_id,
        offset:(page-1)*size,search,sort,direction,filters:scopedFilters}),
    }).then(async response=>{
      if(!response.ok)throw new Error("evidence_request_failed");
      return await response.json() as DeliveryEvidence;
    }).then(result=>{
      if(result.contract!=="jira_delivery_evidence_v2"||result.key!==target.key||
        result.snapshot_id!==data.snapshot_id||result.sort!==({issue_key:"key",created_at:"created",resolved_at:"resolved",severity:"severity",status:"status",priority:"priority",assignee:"assignee"} as Record<DeliveryEvidenceSort,string>)[sort]||
        result.direction!==direction||result.query!==search||
        result.rows.length>size)throw new Error("evidence_contract_mismatch");
      if(!controller.signal.aborted){
        if(search==="")setCohortTotal(result.total);
        setValue(result);setLoading(false);
      }
    }).catch(()=>{
      if(!controller.signal.aborted){setError(true);setLoading(false);}
    });
    return ()=>controller.abort();
  },[target.key,data.snapshot_id,scopedFilters,page,search,sort,direction,retry]);

  const changeSort=(next:DeliveryEvidenceSort)=>{
    setExpanded(null);setPage(1);scroll.current?.scrollTo({top:0});
    if(sort===next)setDirection(d=>d==="asc"?"desc":"asc");
    else{setSort(next);setDirection(next==="created_at"?"desc":"asc");}
  };
  const turnPage=(next:number)=>{
    setPage(next);setExpanded(null);scroll.current?.scrollTo({top:0});
  };
  const openIssue=(row:DeliveryEvidenceItem,button:HTMLButtonElement)=>{
    triggerRef.current=button;setDetailKey(row.issue_key);
  };
  const closeIssue=()=>{
    setDetailKey(null);
    requestAnimationFrame(()=>triggerRef.current?.focus({preventScroll:true}));
  };
  const exportCSV=async()=>{
    if(exporting)return;
    setExporting(true);setExportError(null);
    try{
      const response=await fetch("/api/delivery/evidence",{
        method:"POST",cache:"no-store",
        headers:{"Content-Type":"application/json"},
        body:JSON.stringify({key:target.key,snapshot_id:data.snapshot_id,offset:0,
          search,sort,direction,export:true,filters:scopedFilters}),
      });
      if(!response.ok)throw new Error("export_unavailable");
      const blob=await response.blob();
      if(!blob.type.includes("csv"))throw new Error("export_invalid_response");
      const url=URL.createObjectURL(blob);
      const anchor=document.createElement("a");
      anchor.href=url;anchor.download="jira-"+data.snapshot_id+"-"+target.key.replace(/[^a-z0-9-]/gi,"_")+".csv";
      document.body.appendChild(anchor);anchor.click();anchor.remove();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
    }catch{setExportError("CSV export is unavailable for this scope. Please try again.");}
    finally{setExporting(false);}
  };
  return <>
    <div className="ed-overlay" role="presentation"
      onMouseDown={event=>{if(event.target===event.currentTarget&&!detailKey)onClose();}}>
      <section className="rd-modal rd-activation-modal ed-investigation-modal"
        role="dialog" aria-modal={!detailKey} aria-labelledby="ed-cohort-title" aria-busy={loading}>
        <header className="rd-modal-head ed-investigation-head">
          <div>
            <p>Cohort · Verified Jira snapshot {data.snapshot_id}</p>
            <h2 id="ed-cohort-title">{target.label}</h2>
            <span>{number.format(cohortTotal??(search?value?.source_count:value?.total)??data.core.metric_cohorts[target.key]?.n??0)} issues in the selected population</span>
          </div>
          <button type="button" className="rd-close ed-investigation-close"
            ref={closeRef} onClick={onClose} aria-label="Close issue cohort">×</button>
        </header>
        <div className="ed-investigation-summary">
          <div><span>Cohort issues</span><strong>{number.format(cohortTotal??(search?value?.source_count:value?.total)??0)}</strong></div>
          <div><span>Matching search</span><strong>{number.format(value?.total??0)}</strong></div>
          <div><span>Published sync</span><strong>#{data.snapshot_id}</strong></div>
        </div>
        <div className="rd-drill-toolbar ed-investigation-toolbar">
          <div className="rd-search ed-investigation-search">
            <svg viewBox="0 0 24 24" className="rd-icon" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.7">
              <circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/>
            </svg>
            <input value={query} placeholder="Search key, summary, assignee..."
              aria-label="Search Jira issues in the entire cohort"
              onChange={event=>{setQuery(event.target.value);setPage(1);setExpanded(null);}}/>
            {query?<button type="button" onClick={()=>{setQuery("");setPage(1);}}
              aria-label="Clear search">×</button>:null}
          </div>
          <button type="button" className="ed-investigation-export"
            disabled={loading||exporting||error} onClick={exportCSV}>
            {exporting?"Preparing CSV…":"↓ Export CSV"}
          </button>
        </div>
        <div className="ed-investigation-caption">
          <span>Published Jira issue rows · {sort==="created_at"&&direction==="desc"?"Newest created first":"Sorted by "+sort.replace("_"," ")+" ("+direction+")"}</span>
          {search?<span>Search applied across the entire cohort</span>:null}
        </div>
        <div className="rd-table-wrap ed-investigation-table-wrap" ref={scroll}>
          {error?<div className="ed-investigation-error" role="alert">
            <p>Verified issue evidence is unavailable. No unverified data is shown.</p>
            <button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
          </div>:loading?<EvidenceSkeleton review={target.key==="stage:Code Review"}/>:
          !value||!value.rows.length?<div className="ed-investigation-empty">
            No matching issues in this cohort. Try changing the search.
          </div>:
          <table className="rd-activation-table ed-investigation-table">
            <thead><tr>
              <th scope="col"><span className="ed-screenreader-only">Expand</span></th>
              {sorts.map(({key,label})=><th scope="col" key={key}
                aria-sort={sort===key?(direction==="asc"?"ascending":"descending"):"none"}>
                <button type="button" className="ed-investigation-sort"
                  onClick={()=>changeSort(key)}>
                  {label}<span aria-hidden="true">{sort===key?(direction==="asc"?" ↑":" ↓"):" ↕"}</span>
                </button></th>)}
              {target.key==="stage:Code Review"?<th scope="col">Review dwell</th>:null}
            </tr></thead>
            <tbody>{value.rows.flatMap(row=>{
              const opened=expanded===row.issue_key;
              const cols=target.key==="stage:Code Review"?9:8;
              const master=<tr className={opened?"ed-investigation-row is-expanded":"ed-investigation-row"}
                key={"issue:"+row.issue_key}>
                <td><button type="button" className="rd-expander ed-investigation-expander"
                  aria-expanded={opened} aria-label={(opened?"Collapse ":"Expand ")+row.issue_key}
                  onClick={()=>setExpanded(v=>v===row.issue_key?null:row.issue_key)}>
                  <span aria-hidden="true">{opened?"⌄":"›"}</span></button></td>
                <td><button type="button" className="ed-investigation-key"
                  title={"Open "+row.issue_key+" details"}
                  onClick={event=>openIssue(row,event.currentTarget)}>{row.issue_key} ↗</button></td>
                <td>{date(row.created_at)}</td>
                <td>{date(row.resolved_at)}</td>
                <td>{show(row.severity)}</td>
                <td><span className="ed-investigation-status">{show(row.status)}</span></td>
                <td>{show(row.priority)}</td>
                <td>{show(row.assignee)}</td>
                {target.key==="stage:Code Review"?<td>{duration(row.stage_hours)}</td>:null}
              </tr>;
              if(!opened)return [master];
              const details=<tr className="ed-investigation-expanded" key={"detail:"+row.issue_key}>
                <td colSpan={cols}>
                  <div className="ed-investigation-row-detail">
                    <div className="ed-investigation-summary-text">
                      <span>Summary</span>
                      <p>{show(row.summary)}</p>
                    </div>
                    <div className="ed-investigation-field-grid">
                      {[
                        ["Created",date(row.created_at)],["Resolved",date(row.resolved_at)],
                        ["Severity",show(row.severity)],["Status",show(row.status)],
                        ["Priority",show(row.priority)],["Assignee",show(row.assignee)],
                        ["Issue type",show(row.issue_type)],["Module",show(row.module)],
                        ["Sub-module",show(row.sub_module)],
                      ].map(([label,cell])=><div key={label}>
                        <span>{label}</span><strong>{cell}</strong>
                      </div>)}
                    </div>
                    <button type="button" className="ed-investigation-detail-link"
                      onClick={event=>openIssue(row,event.currentTarget)}>
                      Open full issue investigation →
                    </button>
                  </div>
                </td>
              </tr>;
              return [master,details];
            })}</tbody>
          </table>}
        </div>
        <footer className="rd-modal-foot rd-modal-foot-paginated ed-investigation-foot">
          <div className="rd-table-summary">
            <span>Distinct Jira issues · Published snapshot #{data.snapshot_id}</span>
            <small>{value?"Showing "+number.format(pageStart)+"–"+number.format(pageEnd)+" of "+
              number.format(value.total)+" matching issues":loading?"Loading verified cohort…":"No data available"}</small>
            {exportError?<small role="alert" className="ed-export-error">{exportError}</small>:null}
          </div>
          {value&&pageCount>1?<nav className="rd-pagination" aria-label="Jira issue pages">
            <button type="button" disabled={page<=1} aria-label="Previous page"
              onClick={()=>turnPage(page-1)}>‹</button>
            {pages(page,pageCount).map((item,index)=>item==="…"
              ?<span key={"gap:"+index} className="rd-page-ellipsis">…</span>
              :<button key={item} type="button" aria-current={page===item?"page":undefined}
                onClick={()=>turnPage(item)}>{item}</button>)}
            <button type="button" disabled={page>=pageCount} aria-label="Next page"
              onClick={()=>turnPage(page+1)}>›</button>
          </nav>:null}
        </footer>
      </section>
    </div>
    {detailKey?<DeliveryIssueDetailModal issueKey={detailKey} cohortKey={target.key}
      filters={scopedFilters} snapshotId={data.snapshot_id} onClose={closeIssue}/>:null}
  </>;
}
