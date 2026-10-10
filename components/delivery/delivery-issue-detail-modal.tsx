"use client";

import { useEffect, useRef, useState } from "react";
import type { DeliveryFilters, DeliveryIssueDetail } from "../../lib/delivery/types";

/** Product-style second-level investigation. Returning preserves the primary
 * modal's current search, page, sort and expanded row.
 */
const display=(value:string|null|undefined)=>value?.trim()||"—";
const dt=(iso:string|null|undefined)=>{
  if(!iso)return "—";
  const d=new Date(iso);
  return Number.isNaN(d.getTime())?"—":new Intl.DateTimeFormat("en-GB",{
    day:"2-digit",month:"short",year:"numeric",hour:"2-digit",minute:"2-digit",
    hourCycle:"h23",timeZone:"Asia/Kolkata",
  }).format(d)+" IST";
};
const duration=(value:number|null|undefined)=>{
  if(value===null||value===undefined||!Number.isFinite(value))return "—";
  return value>=48?(value/24).toFixed(1)+"d":value.toFixed(1)+"h";
};

export default function DeliveryIssueDetailModal({issueKey,cohortKey,filters,snapshotId,onClose}:{
  issueKey:string;cohortKey:string;filters:DeliveryFilters;snapshotId:number;onClose:()=>void;
}){
  const [value,setValue]=useState<DeliveryIssueDetail|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState(false);
  const [retry,setRetry]=useState(0);
  const backRef=useRef<HTMLButtonElement>(null);
  useEffect(()=>{
    backRef.current?.focus({preventScroll:true});
    const handle=(event:KeyboardEvent)=>{
      if(event.key==="Escape"){event.preventDefault();event.stopImmediatePropagation();onClose();}
    };
    document.addEventListener("keydown",handle);
    return ()=>document.removeEventListener("keydown",handle);
  },[onClose]);
  useEffect(()=>{
    const controller=new AbortController();
    setLoading(true);setError(false);setValue(null);
    fetch("/api/delivery/issue",{
      method:"POST",cache:"no-store",signal:controller.signal,
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({
        key:cohortKey,issue_key:issueKey,snapshot_id:snapshotId,filters,
      }),
    }).then(async response=>{
      if(!response.ok)throw new Error("jira_issue_read_failed");
      return await response.json() as DeliveryIssueDetail;
    }).then(result=>{
      if(result.contract!=="jira_delivery_issue_v1"||
         result.snapshot_id!==snapshotId||result.issue?.issue_key!==issueKey){
        throw new Error("jira_issue_contract_mismatch");
      }
      if(!controller.signal.aborted){setValue(result);setLoading(false);}
    }).catch(()=>{
      if(!controller.signal.aborted){setError(true);setLoading(false);}
    });
    return ()=>controller.abort();
  },[issueKey,cohortKey,snapshotId,filters.sprint,filters.module,filters.sub_module,filters.severity,filters.assignee,retry]);
  const issue=value?.issue;
  const stats=value?.service_levels;
  const fields=[
    ["SEV",display(issue?.severity)],["STATUS",display(issue?.status)],
    ["PRIORITY",display(issue?.priority)],["TYPE",display(issue?.issue_type)],
    ["MODULE",display(issue?.module)],["SUB-MODULE",display(issue?.sub_module)],
    ["STALE",issue?.stale?"Yes":issue?"No":"—"],
    ["BLOCKED",issue?.blocked?"Yes":issue?"No":"—"],
    ["ASSIGNEE",display(issue?.assignee)],
    ["CREATED",dt(issue?.created_at)],["RESOLVED",dt(issue?.resolved_at)],
  ];
  const sl=[
    ["First response",duration(stats?.first_response_hours)],
    ["ETA deviation",duration(stats?.eta_deviation_hours)],
    ["Reopen count",stats?.reopen_count==null?"—":String(stats.reopen_count)],
    ["QA signoff cycles",stats?.qa_signoff_cycles==null?"—":String(stats.qa_signoff_cycles)],
    ["QA rejected cycles",stats?.qa_rejected_cycles==null?"—":String(stats.qa_rejected_cycles)],
  ];
  return <div className="ed-overlay ed-secondary-overlay" role="presentation"
    onMouseDown={event=>{if(event.target===event.currentTarget)onClose();}}>
    <section className="ed-issue-dialog" role="dialog" aria-modal="true"
      aria-labelledby="ed-issue-detail-title" aria-busy={loading}
      onKeyDown={event=>{
        if(event.key!=="Tab")return;
        const focusable=Array.from(event.currentTarget.querySelectorAll<HTMLElement>(
          'button:not([disabled]),a[href]'
        ));
        if(!focusable.length)return;
        if(event.shiftKey&&document.activeElement===focusable[0]){
          event.preventDefault();focusable[focusable.length-1].focus();
        }else if(!event.shiftKey&&document.activeElement===focusable[focusable.length-1]){
          event.preventDefault();focusable[0].focus();
        }
      }}>
      <header className="ed-issue-head">
        <div>
          <button type="button" ref={backRef} className="ed-issue-back" onClick={onClose}>← Back to issues</button>
          <h2 id="ed-issue-detail-title">{issueKey}</h2>
          <p>{issue?.summary||"Verified Jira issue details"}</p>
        </div>
        <button type="button" className="ed-issue-close" onClick={onClose} aria-label="Close issue details">×</button>
      </header>
      <div className="ed-issue-scroll">
        {loading?<div className="ed-issue-loading" role="status">
          <div className="ed-skeleton-line" style={{width:"92%",height:28}}/>
          <div className="ed-skeleton-line" style={{width:"73%",height:28}}/>
          {Array.from({length:4},(_,i)=><div key={i} className="ed-skeleton-line"
            style={{width:(95-i*9)+"%",height:56}}/>)}
          <span className="ed-screenreader-only">Loading verified Jira issue details…</span>
        </div>:error||!value?<div className="ed-issue-unavailable" role="alert">
          <p>Verified details are unavailable. No unverified data is shown.</p>
          <button type="button" onClick={()=>setRetry(v=>v+1)}>Try again</button>
        </div>:<>
          <div className="ed-issue-field-pills">
            {fields.map(([name,raw])=><span key={name} className="ed-issue-pill">
              <small>{name}</small><strong>{raw}</strong>
            </span>)}
          </div>
          <section className="ed-issue-section" aria-label="Service levels">
            <h3>Service levels</h3>
            <div className="ed-issue-levels">
              {sl.map(([name,val])=><div key={name}>
                <span>{name}</span><strong>{val}</strong>
              </div>)}
            </div>
            <p className="ed-issue-caveat">Unavailable service measures are shown as —, never inferred.</p>
          </section>
          <section className="ed-issue-section" aria-label="Status trail">
            <h3>Status trail</h3>
            {value.status_trail.length?<div className="ed-issue-trail-wrap">
              <table className="ed-issue-trail-table">
                <thead><tr><th>Status</th><th>Entered</th><th>Dwell</th></tr></thead>
                <tbody>{value.status_trail.map((entry,index)=><tr key={entry.entered_at+"-"+index}>
                  <th scope="row">{display(entry.status)}</th>
                  <td>{dt(entry.entered_at)}</td><td>{duration(entry.dwell_hours)}</td>
                </tr>)}</tbody>
              </table>
            </div>:<p className="ed-issue-muted">No Jira status transitions published.</p>}
          </section>
          <section className="ed-issue-section" aria-label="Comments">
            <h3>Comments <small>({value.comments.length}{value.comments.length===30?"+":""})</small></h3>
            {value.comments.length?<div className="ed-issue-comments">
              {value.comments.map((comment,index)=><div key={comment.created_at+"-"+index}>
                <header><strong>{display(comment.author)}</strong><span>{dt(comment.created_at)}</span></header>
                <p>{comment.text||"Comment has no published text."}</p>
              </div>)}
            </div>:<p className="ed-issue-muted">No comments published.</p>}
          </section>
          <section className="ed-issue-section" aria-label="Linked issues">
            <h3>Links <small>({value.links.length}{value.links.length===30?"+":""})</small></h3>
            {value.links.length?<ul className="ed-issue-links">
              {value.links.map((item,index)=><li key={(item.issue_key||"unknown")+"-"+index}>
                <span>{display(item.description||item.type)}</span>
                {item.issue_key&&/^SPEND-[0-9]+$/.test(item.issue_key)?<a
                  href={"https://karbonworks.atlassian.net/browse/"+encodeURIComponent(item.issue_key)}
                  target="_blank" rel="noopener noreferrer">{item.issue_key}</a>:
                  <span>{display(item.issue_key)}</span>}
              </li>)}
            </ul>:<p className="ed-issue-muted">No linked Jira issues published.</p>}
          </section>
        </>}
      </div>
      <footer className="ed-issue-footer">
        <a href={"https://karbonworks.atlassian.net/browse/"+encodeURIComponent(issueKey)}
          target="_blank" rel="noopener noreferrer">Open in Jira</a>
      </footer>
    </section>
  </div>;
}
