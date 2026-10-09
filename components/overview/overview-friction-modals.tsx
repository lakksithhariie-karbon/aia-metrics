"use client";

import {useEffect,useMemo,useRef,useState} from "react";
import type {
 FrictionSummary,FrictionKey,FrictionIssue,FrictionPeriod,FrictionSegment,
 FrictionCompanyList,FrictionCompanyDetail,FrictionCompanyRow,FrictionUserRow,
} from "../../lib/overview/friction";

const number=new Intl.NumberFormat("en-US");
const SIZE=8;
function Icon({name}:{name:"close"|"left"|"right"|"down"|"search"}){
 return <svg className="rd-icon" aria-hidden="true"><use href={"#i-"+name}/></svg>;
}
function when(value:string|null|undefined):string{
 if(!value)return "Not recorded";
 const d=new Date(value);
 if(Number.isNaN(d.getTime()))return "Not recorded";
 return d.toLocaleString("en-GB",{
  timeZone:"Asia/Kolkata",day:"numeric",month:"short",year:"numeric",
  hour:"2-digit",minute:"2-digit",
 })+" IST";
}
function date(value:string|null|undefined):string{
 if(!value)return "—";
 const d=new Date(value.length===10?value+"T12:00:00Z":value);
 if(Number.isNaN(d.getTime()))return "—";
 return d.toLocaleDateString("en-GB",{
  timeZone:value.length===10?"UTC":"Asia/Kolkata",
  day:"numeric",month:"short",year:"numeric",
 });
}
function pages(current:number,total:number):Array<number|"…">{
 const indexes=[...new Set([1,current-1,current,current+1,total])]
  .filter(x=>x>0&&x<=total).sort((a,b)=>a-b);
 const r:Array<number|"…">=[];
 indexes.forEach((n,i)=>{if(i&&n-indexes[i-1]>1)r.push("…");r.push(n);});
 return r;
}
async function request<T>(body:Record<string,unknown>,signal:AbortSignal):Promise<T>{
 const r=await fetch("/api/overview-friction",{
  method:"POST",headers:{"Content-Type":"application/json"},
  cache:"no-store",body:JSON.stringify(body),signal,
 });
 if(!r.ok)throw new Error(r.status===409||r.status===404
  ?"The selected snapshot changed. Refresh the dashboard."
  :"Couldn't load the company evidence. Try again.");
 return await r.json() as T;
}
function countFor(issue:FrictionIssue,period:FrictionPeriod,segment:FrictionSegment):number{
 const row=issue[period];
 if(segment==="eligible")return row.eligible;
 if(segment==="affected")return row.affected;
 if(segment==="later_success")return row.followup;
 return row.needs_review;
}
export interface FrictionTarget{
 key:FrictionKey;
 period:FrictionPeriod;
 segment:FrictionSegment;
}

export default function FrictionDrillModal({
 summary,target,onClose,
}:{
 summary:FrictionSummary;target:FrictionTarget;onClose:()=>void;
}){
 const issue=summary.rows.find(r=>r.key===target.key)!;
 const [period,setPeriod]=useState<FrictionPeriod>(target.period);
 const [segment,setSegment]=useState<FrictionSegment>(target.segment);
 const [query,setQuery]=useState("");
 const [deferred,setDeferred]=useState("");
 const [page,setPage]=useState(1);
 const [expanded,setExpanded]=useState<string|null>(null);
 const [list,setList]=useState<FrictionCompanyList|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const [companyId,setCompanyId]=useState<string|null>(null);
 const returnFocus=useRef<HTMLButtonElement|null>(null);
 const scroll=useRef<HTMLDivElement>(null);
 const cache=useRef(new Map<string,FrictionCompanyList>());

 useEffect(()=>{
  const t=setTimeout(()=>setDeferred(query),260);
  return ()=>clearTimeout(t);
 },[query]);
 useEffect(()=>{
  setPage(1);setExpanded(null);scroll.current?.scrollTo({top:0});
 },[period,segment,deferred]);

 const key=[summary.snapshotId,issue.key,period,segment,deferred,page].join("|");
 const expected=countFor(issue,period,segment);
 useEffect(()=>{
  const abort=new AbortController();
  const saved=cache.current.get(key);
  if(saved){setList(saved);setError(null);setLoading(false);return ()=>abort.abort();}
  setLoading(true);setList(null);setError(null);
  request<FrictionCompanyList>({
   action:"list",snapshot_id:summary.snapshotId,
   issue:issue.key,period,segment,query:deferred,page,page_size:SIZE,
  },abort.signal).then(result=>{
   if(abort.signal.aborted)return;
   if(result.contract!=="observed_company_friction_list_v1" ||
      result.snapshot_id!==summary.snapshotId||result.issue_key!==issue.key||
      result.period!==period||result.segment!==segment||
      result.segment_total!==expected)
    throw new Error("The company population doesn't reconcile with this issue. Refresh.");
   cache.current.set(key,result);setList(result);
  }).catch(e=>{
   if(!abort.signal.aborted)setError(e instanceof Error?e.message:"Data unavailable");
  }).finally(()=>{if(!abort.signal.aborted)setLoading(false)});
  return ()=>abort.abort();
 },[key,summary.snapshotId,issue.key,period,segment,deferred,page,retry,expected]);
 useEffect(()=>{
  const old=document.body.style.overflow;document.body.style.overflow="hidden";
  return ()=>{document.body.style.overflow=old};
 },[]);
 useEffect(()=>{
  function keydown(e:KeyboardEvent){
   if(e.key!=="Escape")return;
   e.preventDefault();
   if(companyId)setCompanyId(null);
   else onClose();
  }
  window.addEventListener("keydown",keydown);
  return ()=>window.removeEventListener("keydown",keydown);
 },[companyId,onClose]);
 const current=issue[period];
 const numPages=Math.max(1,Math.ceil((list?.total??0)/SIZE));
 const first=list?.rows.length?(page-1)*SIZE+1:0;
 const last=list?.rows.length?first+list.rows.length-1:0;
 function openCompany(c:FrictionCompanyRow,node:HTMLButtonElement){
  returnFocus.current=node;setCompanyId(c.id);
 }
 return <>
  <div className="rd-overlay" role="presentation">
   <section className="rd-modal rd-activation-modal po-friction-drill-modal"
    role="dialog" aria-modal="true" aria-labelledby="po-friction-drill-title">
    <header className="rd-modal-head">
     <div>
      <p>Product Overview · Issues that need attention</p>
      <h2 id="po-friction-drill-title">{issue.label}</h2>
      <span>{issue.kind} · {number.format(expected)} selected companies ·
       {" "}{period==="current"?"Current":"Previous"} 28 days</span>
     </div>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Close issue drill"><Icon name="close"/></button>
    </header>
    <div className="po-friction-modal-summary">
     <div><span>Eligible companies</span><strong>{number.format(current.eligible)}</strong></div>
     <div><span>Had a failure / revert</span><strong>{number.format(current.affected)}</strong></div>
     <div><span>No later success recorded</span><strong>{number.format(current.needs_review)}</strong></div>
    </div>
    <div className="rd-drill-toolbar po-friction-drill-toolbar">
     <div className="po-friction-drill-tabs">
      <div className="rd-status-tabs" aria-label="Reporting period">
       {(["current","previous"] as const).map(v=><button type="button" key={v}
        aria-pressed={period===v} onClick={()=>setPeriod(v)}>
        {v==="current"?"Current 28d":"Previous 28d"}
       </button>)}
      </div>
      <div className="rd-status-tabs" aria-label="Company status">
       {([
        ["needs_review","Needs review"],["later_success","Later success"],
        ["affected","All affected"],["eligible","All eligible"],
       ] as const).map(([v,label])=><button key={v} type="button"
        aria-pressed={segment===v} onClick={()=>setSegment(v)}>
        {label}<span>{number.format(countFor(issue,period,v))}</span>
       </button>)}
      </div>
     </div>
     <div className="rd-search">
      <Icon name="search"/>
      <input aria-label="Search issue companies" value={query}
       onChange={e=>setQuery(e.currentTarget.value)} placeholder="Search companies"/>
      {query?<button type="button" aria-label="Clear search"
       onClick={()=>setQuery("")}><Icon name="close"/></button>:null}
     </div>
    </div>
    <div className="rd-table-wrap po-friction-drill-scroll" ref={scroll}>
     {loading?<div className="rd-loading">Loading observed company events…</div>:
     error?<div className="rd-empty po-usage-error">
      <span>{error}</span><button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
     </div>:!list?<div className="rd-empty">No verified records available</div>:
     <table className="rd-activation-table po-friction-company-table">
      <thead><tr>
       <th scope="col"><span className="sr-only">Expand users</span></th>
       <th scope="col">Company</th>
       <th scope="col">Follow-up status</th>
       <th scope="col">Failed / reverted</th>
       <th scope="col">Success events</th>
       <th scope="col">Last failed / reverted</th>
       <th scope="col">Later success</th>
       <th scope="col">Users</th>
      </tr></thead>
      <tbody>{list.rows.length?list.rows.flatMap(c=>{
       const open=expanded===c.id;
       const state=c.failed_events===0?"Not affected":
         c.followup_at?"Later success":"Needs review";
       const parent=<tr key={"company:"+c.id} className={open?"is-expanded":""}>
        <td><button type="button" className="rd-expander"
         aria-label={(open?"Collapse ":"Expand ")+c.name}
         aria-expanded={open} onClick={()=>setExpanded(open?null:c.id)}>
         <Icon name={open?"down":"right"}/></button></td>
        <td><button type="button" className="rd-company-link"
         onClick={e=>openCompany(c,e.currentTarget)}>
         <strong>{c.name}</strong>
         <span>{c.is_test?"Test company · ":""}Full workflow evidence →</span>
        </button></td>
        <td><span className={"po-friction-state "+(c.failed_events===0?"is-clear":
          c.followup_at?"is-success":"is-open")}>{state}</span></td>
        <td>{number.format(c.failed_events)}</td>
        <td>{number.format(c.success_events)}</td>
        <td>{when(c.last_failure_at)}</td>
        <td>{when(c.followup_at)}</td>
        <td>{number.format(c.observed_users)}</td>
       </tr>;
       if(!open)return [parent];
       const nested=c.users.map(u=><tr className="rd-user-row" key={"person:"+c.id+":"+u.id}>
        <td/>
        <td><span className="rd-user-indent">{u.email}</span></td>
        <td/><td>{number.format(u.failures)}</td>
        <td>{number.format(u.successes)}</td>
        <td>{when(u.last_at)}</td>
        <td/><td>{number.format(u.attempts)} attempts</td>
       </tr>);
       return [parent,...nested];
      }):<tr><td colSpan={8}><div className="rd-empty">
       No companies match this selection.
      </div></td></tr>}</tbody>
     </table>}
    </div>
    <footer className="rd-modal-foot rd-modal-foot-paginated">
     <div className="rd-table-summary">
      <span>Later success is company-level evidence, not confirmed resolution</span>
      <small>{list?"Showing "+first+"–"+last+" of "+
       number.format(list.total)+" matching companies":
       "Snapshot #"+summary.snapshotId}</small>
     </div>
     {list&&numPages>1?<nav className="rd-pagination" aria-label="Issue company pages">
      <button type="button" aria-label="Previous page" disabled={page<=1}
       onClick={()=>setPage(n=>n-1)}><Icon name="left"/></button>
      {pages(page,numPages).map((n,i)=>n==="…"
       ?<span key={"dots:"+i} className="rd-page-ellipsis">…</span>
       :<button key={n} type="button" aria-current={n===page?"page":undefined}
        onClick={()=>setPage(n)}>{n}</button>)}
      <button type="button" aria-label="Next page" disabled={page>=numPages}
       onClick={()=>setPage(n=>n+1)}><Icon name="right"/></button>
     </nav>:null}
    </footer>
   </section>
  </div>
  {companyId?<FrictionCompanyModal
   snapshotId={summary.snapshotId}
   issue={issue} period={period} segment={segment} companyId={companyId}
   onClose={()=>{
    setCompanyId(null);
    requestAnimationFrame(()=>returnFocus.current?.focus({preventScroll:true}));
   }}
  />:null}
 </>;
}

function FrictionCompanyModal({
 snapshotId,issue,period,segment,companyId,onClose,
}:{
 snapshotId:number;issue:FrictionIssue;period:FrictionPeriod;
 segment:FrictionSegment;companyId:string;onClose:()=>void;
}){
 const [detail,setDetail]=useState<FrictionCompanyDetail|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const [tab,setTab]=useState<"overview"|"timeline"|"users">("overview");

 useEffect(()=>{
  const abort=new AbortController();
  setLoading(true);setDetail(null);setError(null);
  request<FrictionCompanyDetail>({
   action:"company",snapshot_id:snapshotId,issue:issue.key,
   period,segment,company_id:companyId,
  },abort.signal).then(result=>{
   if(abort.signal.aborted)return;
   if(result.contract!=="observed_company_friction_company_v1"
    ||result.snapshot_id!==snapshotId||result.issue_key!==issue.key
    ||result.company.id!==companyId||result.period!==period||result.segment!==segment)
    throw new Error("The company details don't match the selected issue population.");
   setDetail(result);
  }).catch(e=>{
   if(!abort.signal.aborted)setError(e instanceof Error?e.message:"Company unavailable");
  }).finally(()=>{if(!abort.signal.aborted)setLoading(false)});
  return ()=>abort.abort();
 },[snapshotId,issue.key,period,segment,companyId,retry]);

 const milestones=useMemo(()=>{
  if(!detail)return [];
  return [
   ["Company created",detail.milestones.company_created_at],
   ["Integration recorded",detail.milestones.integration_at],
   ["First failure / revert",detail.summary.first_failure_at],
   ["Latest failure / revert",detail.summary.last_failure_at],
   ["Later workflow success",detail.summary.followup_at],
  ] as const;
 },[detail]);

 return <div className="rd-overlay rd-overlay-level-2" role="presentation">
  <section className="rd-modal rd-company-modal po-friction-company-modal"
   role="dialog" aria-modal="true" aria-labelledby="po-friction-company-title">
   <header className="rd-company-head">
    <div className="rd-company-topline">
     <button type="button" className="rd-back" onClick={onClose}>
      <Icon name="left"/> Back to issue companies
     </button>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Back to issue companies"><Icon name="close"/></button>
    </div>
    <div>
     <div>
      <p>Company workflow evidence · {period==="current"?"Current":"Previous"} 28 days</p>
      <h2 id="po-friction-company-title">{detail?.company.name??"Company profile"}</h2>
     </div>
     <div className="rd-company-tags">
      <span>{issue.label}</span>
      <span>{issue.kind}</span>
      {detail?.company.is_test?<span>Test</span>:null}
     </div>
    </div>
   </header>
   <div className="rd-company-scroll">
    {loading?<div className="rd-loading">Loading verified workflow evidence…</div>
    :error||!detail?<div className="rd-empty po-usage-error">
     <span>{error??"Company evidence unavailable"}</span>
     <button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
     <button type="button" onClick={onClose}>Back</button>
    </div>:<>
     <div className="po-company-context">
      <strong>Reporting window</strong>
      <span>{when(detail.window.start)} to {when(detail.window.end)}</span>
      <small>Only the selected company and workflow</small>
     </div>
     <div className="rd-health-strip po-company-health">
      <div><span>Workflow events</span><strong>{number.format(detail.summary.attempts)}</strong></div>
      <div><span>Failed / reverted</span><strong>{number.format(detail.summary.failures)}</strong></div>
      <div><span>Success events</span><strong>{number.format(detail.summary.successes)}</strong></div>
      <div><span>Observed users</span><strong>{number.format(detail.summary.users)}</strong></div>
     </div>
     <p className="po-friction-company-evidence-note">
      {detail.summary.failures===0?"No failure or reversion recorded in this period.":
       detail.summary.followup_at
        ?"A later success was recorded in the same company and workflow, after its latest failure/reversion."
        :"No later success in the same workflow was recorded by the end of this period."}
      {" "}This does not identify whether the same transaction or upload was resolved.
     </p>
     <div className="rd-status-tabs po-company-tabs" aria-label="Company evidence section">
      {(["overview","timeline","users"] as const).map(key=>
       <button type="button" aria-pressed={tab===key} key={key}
        onClick={()=>setTab(key)}>
        {key==="timeline"?"Event timeline":key[0].toUpperCase()+key.slice(1)}
       </button>)}
     </div>

     {tab==="overview"?<>
      <section className="rd-lifecycle-card">
       <div className="rd-section-title">
        <div><h3>Recorded workflow milestones</h3>
         <p>Company and issue timestamps from tracked events</p></div>
       </div>
       <div className="rd-timeline">
        {milestones.map(([label,at],i)=><div key={label}
         className={"rd-milestone "+(!at?"is-empty":"")}>
         <span className="rd-dot"/>{i<4?<i/>:null}
         <small>{label}</small><strong title={when(at)}>{date(at)}</strong>
        </div>)}
       </div>
      </section>
      <div className="rd-detail-grid po-friction-evidence-grid">
       <section className="rd-detail-card">
        <div className="rd-section-title">
         <div><h3>Workflow activity by week</h3>
          <p>IST calendar weeks within selected reporting period</p></div>
        </div>
        <div className="po-friction-weeks">
         <table><thead><tr>
          <th>Week</th><th>Failures</th><th>Successes</th><th>Users</th>
         </tr></thead><tbody>
          {detail.weeks.map(w=><tr key={w.week_start}>
           <td>{date(w.week_start)}</td>
           <td>{number.format(w.failures)}</td>
           <td>{number.format(w.successes)}</td>
           <td>{number.format(w.active_users)}</td>
          </tr>)}
         </tbody></table>
        </div>
       </section>
       <section className="rd-detail-card">
        <div className="rd-section-title">
         <div><h3>Latest workflow status</h3><p>Observed, not confirmed resolution</p></div>
        </div>
        <div className="po-company-context-list">
         <div><span>First failure / revert</span><strong>{when(detail.summary.first_failure_at)}</strong></div>
         <div><span>Latest failure / revert</span><strong>{when(detail.summary.last_failure_at)}</strong></div>
         <div><span>Later workflow success</span><strong>{when(detail.summary.followup_at)}</strong></div>
         <div><span>Most recent event</span><strong>{when(detail.summary.last_event_at)}</strong></div>
        </div>
       </section>
      </div>
     </>:null}

     {tab==="timeline"?<section className="rd-weeks-card po-company-week-card">
      <div className="rd-section-title">
       <div><h3>Recent issue events</h3>
        <p>Latest 60 attempts in this company's selected workflow and period</p></div>
      </div>
      <div className="rd-weeks-wrap po-friction-events">
       <table><thead><tr>
        <th>When</th><th>Event</th><th>Result</th><th>Type / action</th><th>User</th>
       </tr></thead><tbody>
        {detail.events.map((e,i)=><tr key={e.at+":"+i}>
         <td>{when(e.at)}</td>
         <td>{e.event}</td>
         <td><span className={"po-friction-state "+(e.is_failure?"is-open":"is-success")}>
          {e.is_failure?issue.kind==="Rework"?"Reverted":"Failed":"Success"}
         </span></td>
         <td>{e.action||e.activity_type||"—"}</td><td>{e.email}</td>
        </tr>)}
       </tbody></table>
      </div>
     </section>:null}

     {tab==="users"?<section className="rd-weeks-card po-company-week-card">
      <div className="rd-section-title">
       <div><h3>Users involved</h3>
        <p>Workflow events attributed to people in this company</p></div>
      </div>
      <div className="rd-weeks-wrap po-friction-users">
       <table><thead><tr>
        <th>User</th><th>Events</th><th>Failed / reverted</th>
        <th>Successes</th><th>Last event</th>
       </tr></thead><tbody>
        {detail.users.map(u=><tr key={u.id}>
         <td><strong>{u.email}</strong></td>
         <td>{number.format(u.attempts)}</td>
         <td>{number.format(u.failures)}</td>
         <td>{number.format(u.successes)}</td>
         <td>{when(u.last_at)}</td>
        </tr>)}
       </tbody></table>
      </div>
     </section>:null}
     <p className="po-company-freshness">
      Snapshot #{detail.snapshot_id} · Source watermark {when(detail.source_watermark_at)}
      {" · "}No individual transaction or upload ID is available for verified resolution matching.
     </p>
    </>}
   </div>
  </section>
 </div>;
}
