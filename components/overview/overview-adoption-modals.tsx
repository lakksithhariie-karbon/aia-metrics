"use client";

import { useEffect,useMemo,useRef,useState } from "react";
import type {
 AdoptionSummary,AdoptionSegment,AdoptionList,AdoptionCompany,AdoptionCompanyDetail,
} from "../../lib/overview/adoption";

const nf=new Intl.NumberFormat("en-US");
const PAGE_SIZE=8;
export interface AdoptionDrillTarget {
  title:string;context:string;initial:AdoptionSegment;
  tabs:Array<{key:AdoptionSegment;label:string;count:number}>;
}
function Icon({name}:{name:"close"|"left"|"right"|"down"|"search"}){
 return <svg className="rd-icon" aria-hidden="true"><use href={"#i-"+name}/></svg>;
}
function time(value:string|null|undefined){
 if(!value)return "Not recorded";
 const d=new Date(value);
 if(Number.isNaN(d.getTime()))return "Not recorded";
 return d.toLocaleString("en-GB",{
  timeZone:"Asia/Kolkata",day:"numeric",month:"short",
  year:"numeric",hour:"2-digit",minute:"2-digit",
 })+" IST";
}
function date(value:string|null|undefined){
 if(!value)return "—";
 const d=new Date(value);
 if(Number.isNaN(d.getTime()))return "—";
 return d.toLocaleDateString("en-GB",{timeZone:"Asia/Kolkata",
  day:"numeric",month:"short",year:"numeric"});
}
function pages(current:number,total:number):Array<number|"ellipsis">{
 const values=[...new Set([1,current-1,current,current+1,total])]
 .filter(i=>i>=1&&i<=total).sort((a,b)=>a-b);
 const result:Array<number|"ellipsis">=[];
 for(let i=0;i<values.length;i++){
  if(i&&values[i]-values[i-1]>1)result.push("ellipsis");
  result.push(values[i]);
 }
 return result;
}
async function post<T>(body:Record<string,unknown>,signal:AbortSignal):Promise<T>{
 const response=await fetch("/api/overview-adoption",{
  method:"POST",headers:{"Content-Type":"application/json"},
  cache:"no-store",signal,body:JSON.stringify(body),
 });
 if(!response.ok)throw new Error(response.status===409||response.status===404
  ?"A new snapshot is available. Refresh the dashboard."
  :"Could not load live company data. Please try again.");
 return await response.json() as T;
}
function status(c:AdoptionCompany){
 if(c.value_at)return "Reached value";
 if(c.sync_after_core_at)return "Reached sync";
 if(c.active_weeks>=2)return "Sustained";
 if(c.first_core_7d_at)return "Started work";
 return "Not started";
}

export default function AdoptionDrillModal({
 summary,target,onClose,
}:{
 summary:AdoptionSummary;target:AdoptionDrillTarget;onClose:()=>void;
}){
 const [segment,setSegment]=useState<AdoptionSegment>(target.initial);
 const [query,setQuery]=useState("");
 const [deferred,setDeferred]=useState("");
 const [page,setPage]=useState(1);
 const [rows,setRows]=useState<AdoptionList|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const [expanded,setExpanded]=useState<Set<string>>(new Set());
 const [detailId,setDetailId]=useState<string|null>(null);
 const [focusReturn,setFocusReturn]=useState<HTMLButtonElement|null>(null);
 const cache=useRef(new Map<string,AdoptionList>());
 const tableRef=useRef<HTMLDivElement>(null);
 useEffect(()=>{
  const t=setTimeout(()=>setDeferred(query),250);
  return ()=>clearTimeout(t);
 },[query]);
 useEffect(()=>{
  setPage(1);setExpanded(new Set());tableRef.current?.scrollTo({top:0});
 },[segment,deferred]);
 const key=[summary.snapshotId,segment,deferred,page].join("|");
 useEffect(()=>{
  const controller=new AbortController();
  const cached=cache.current.get(key);
  if(cached){setRows(cached);setLoading(false);setError(null);return ()=>controller.abort()}
  setLoading(true);setError(null);setRows(null);
  post<AdoptionList>({
   action:"list",snapshot_id:summary.snapshotId,
   segment,query:deferred,page,page_size:PAGE_SIZE,
  },controller.signal).then(data=>{
   if(controller.signal.aborted)return;
   const expected=target.tabs.find(t=>t.key===segment)?.count;
   if(data.contract!=="mature_independent_adoption_companies_v1"
   ||data.snapshot_id!==summary.snapshotId||data.segment!==segment
   ||expected===undefined||data.segment_total!==expected){
    throw new Error("Company membership doesn't reconcile to this snapshot. Refresh.");
   }
   cache.current.set(key,data);
   setRows(data);
  }).catch(e=>{
   if(!controller.signal.aborted)setError(e instanceof Error?e.message:"Data unavailable");
  }).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return ()=>controller.abort();
 },[key,summary.snapshotId,segment,deferred,page,retry,target.tabs]);
 useEffect(()=>{
  const was=document.body.style.overflow;document.body.style.overflow="hidden";
  return ()=>{document.body.style.overflow=was};
 },[]);
 useEffect(()=>{
  const keydown=(e:KeyboardEvent)=>{
   if(e.key!=="Escape")return;
   e.preventDefault();
   if(detailId)setDetailId(null);else onClose();
  };
  window.addEventListener("keydown",keydown);
  return ()=>window.removeEventListener("keydown",keydown);
 },[detailId,onClose]);
 function toggle(id:string){
  setExpanded(prev=>prev.has(id)?new Set():new Set([id]));
 }
 const numPages=Math.max(1,Math.ceil((rows?.total??0)/PAGE_SIZE));
 const first=rows?.rows.length?(page-1)*PAGE_SIZE+1:0;
 const last=rows?.rows.length?first+rows.rows.length-1:0;
 const activeCount=target.tabs.find(t=>t.key===segment)?.count??0;

 return <>
  <div className="rd-overlay" role="presentation">
   <section className="rd-modal rd-activation-modal po-adoption-drill-modal"
    role="dialog" aria-modal="true" aria-labelledby="po-adoption-drill-title">
    <header className="rd-modal-head">
     <div>
      <p>Adoption &amp; Value · Mature 28-day integration cohort</p>
      <h2 id="po-adoption-drill-title">{target.title}</h2>
      <span>{nf.format(activeCount)} companies · {target.context}</span>
     </div>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Close adoption drill"><Icon name="close"/></button>
    </header>
    <div className="po-adoption-drill-summary">
     <div><span>Eligible integrations</span><strong>{nf.format(summary.total)}</strong></div>
     <div><span>Selected companies</span><strong>{nf.format(activeCount)}</strong></div>
     <div><span>Reporting basis</span><strong>First 28 days</strong></div>
    </div>
    <div className="rd-drill-toolbar po-adoption-drill-toolbar">
     <div className="rd-status-tabs" aria-label="Company stage">
      {target.tabs.map(tab=><button key={tab.key} type="button"
       aria-pressed={segment===tab.key} onClick={()=>setSegment(tab.key)}>
       {tab.label}<span>{nf.format(tab.count)}</span>
      </button>)}
     </div>
     <div className="rd-search">
      <Icon name="search"/>
      <input aria-label="Search companies" placeholder="Search companies"
       value={query} onChange={e=>setQuery(e.currentTarget.value)}/>
      {query?<button type="button" aria-label="Clear search"
       onClick={()=>setQuery("")}><Icon name="close"/></button>:null}
     </div>
    </div>
    <div className="rd-table-wrap po-adoption-table-wrap" ref={tableRef}>
     {loading?<div className="rd-loading">Loading verified companies…</div>:
      error?<div className="rd-empty po-usage-error">
       <span>{error}</span><button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
      </div>:!rows?<div className="rd-empty">No data available.</div>:
      <table className="rd-activation-table po-adoption-table">
       <thead><tr>
        <th scope="col"><span className="sr-only">Expand</span></th>
        <th scope="col">Company</th>
        <th scope="col">Status</th>
        <th scope="col">Integration</th>
        <th scope="col">First core</th>
        <th scope="col">Weeks</th>
        <th scope="col">AP</th><th scope="col">AR</th><th scope="col">Transaction</th>
       </tr></thead>
       <tbody>
        {rows.rows.length?rows.rows.flatMap(c=>{
         const open=expanded.has(c.id);
         const parent=<tr key={"company:"+c.id} className={open?"is-expanded":""}>
          <td><button className="rd-expander" type="button"
           aria-expanded={open} aria-label={(open?"Collapse ":"Expand ")+c.name}
           onClick={()=>toggle(c.id)}><Icon name={open?"down":"right"}/></button></td>
          <td><button type="button" className="rd-company-link"
           onClick={e=>{setFocusReturn(e.currentTarget);setDetailId(c.id)}}>
           <strong>{c.name}</strong><span>{c.integration_type}{c.is_test?" · Test":""} · View full profile</span>
          </button></td>
          <td><span className={"po-adoption-status "+
           (c.value_at?"is-value":c.first_core_7d_at?"is-started":"is-stalled")}>
           {status(c)}
          </span></td>
          <td>{date(c.integration_at)}</td><td>{date(c.first_core_28d_at)}</td>
          <td>{nf.format(c.active_weeks)}/4</td>
          <td>{nf.format(c.modules.ap)}</td>
          <td>{nf.format(c.modules.ar)}</td>
          <td>{nf.format(c.modules.transactions)}</td>
         </tr>;
         if(!open)return [parent];
         if(!c.users.length)return [parent,<tr className="rd-user-row"
          key={"none:"+c.id}><td/><td colSpan={8}>
           <span className="rd-user-indent">No independent core activity observed in first 28 days</span>
          </td></tr>];
         const users=c.users.slice(0,5).map(u=><tr className="rd-user-row"
          key={"person:"+c.id+":"+u.id}>
          <td/><td><span className="rd-user-indent">{u.email}</span></td>
          <td/><td/><td>{date(u.last_core_at)}</td><td>{nf.format(u.core_actions)} actions</td>
          <td>{nf.format(u.modules.ap)}</td>
          <td>{nf.format(u.modules.ar)}</td>
          <td>{nf.format(u.modules.transactions)}</td>
         </tr>);
         if(c.users.length>5)users.push(<tr className="rd-user-row" key={"more:"+c.id}>
          <td/><td colSpan={8}>
           <button type="button" className="po-adoption-more"
            onClick={e=>{setFocusReturn(e.currentTarget);setDetailId(c.id)}}>
            +{c.users.length-5} more users · View full company profile
           </button>
          </td></tr>);
         return [parent,...users];
        }):<tr><td colSpan={9}><div className="rd-empty">
         No companies match your search.
        </div></td></tr>}
       </tbody>
      </table>}
    </div>
    <footer className="rd-modal-foot rd-modal-foot-paginated">
     <div className="rd-table-summary">
      <span>Distinct client companies · Source-aligned integration cohort</span>
      <small>{rows?"Showing "+first+"–"+last+" of "+
       nf.format(rows.total)+" matching companies":
       "Snapshot #"+summary.snapshotId}</small>
     </div>
     {rows&&numPages>1?<nav className="rd-pagination" aria-label="Company pages">
      <button type="button" disabled={page===1}
       aria-label="Previous page" onClick={()=>setPage(n=>n-1)}><Icon name="left"/></button>
      {pages(page,numPages).map((x,i)=>x==="ellipsis"?
       <span key={"ellipsis:"+i} className="rd-page-ellipsis">…</span>:
       <button type="button" key={x} aria-current={x===page?"page":undefined}
        onClick={()=>setPage(x)}>{x}</button>)}
      <button type="button" disabled={page===numPages}
       aria-label="Next page" onClick={()=>setPage(n=>n+1)}><Icon name="right"/></button>
     </nav>:null}
    </footer>
   </section>
  </div>
  {detailId?<AdoptionCompanyDetailModal
   snapshotId={summary.snapshotId} companyId={detailId}
   onClose={()=>{setDetailId(null);requestAnimationFrame(()=>focusReturn?.focus({preventScroll:true}))}}
  />:null}
 </>;
}

function AdoptionCompanyDetailModal({
 snapshotId,companyId,onClose,
}:{
 snapshotId:number;companyId:string;onClose:()=>void;
}){
 const [data,setData]=useState<AdoptionCompanyDetail|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const [tab,setTab]=useState<"overview"|"activity"|"users">("overview");
 useEffect(()=>{
  const controller=new AbortController();
  setLoading(true);setError(null);setData(null);
  post<AdoptionCompanyDetail>({
   action:"company",snapshot_id:snapshotId,company_id:companyId,
  },controller.signal).then(result=>{
   if(controller.signal.aborted)return;
   if(result.contract!=="mature_independent_adoption_company_v1"||
    result.snapshot_id!==snapshotId||result.company.id!==companyId)
    throw new Error("Company profile does not match the selected snapshot.");
   setData(result);
  }).catch(e=>{
   if(!controller.signal.aborted)setError(e instanceof Error?e.message:"Profile unavailable");
  }).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return ()=>controller.abort();
 },[snapshotId,companyId,retry]);
 const milestones=useMemo(()=>{
  if(!data)return [];
  return [
   ["Integration",data.milestones.integration_at],
   ["Training sync",data.milestones.training_sync_at],
   ["Independent core",data.milestones.first_core_28d_at],
   ["Post-work sync",data.milestones.sync_after_core_at],
   ["Value conversion",data.milestones.value_at],
  ] as const;
 },[data]);

 return <div className="rd-overlay rd-overlay-level-2" role="presentation">
  <section className="rd-modal rd-company-modal po-adoption-company-modal"
   role="dialog" aria-modal="true" aria-labelledby="adoption-company-title">
   <header className="rd-company-head">
    <div className="rd-company-topline">
     <button type="button" className="rd-back" onClick={onClose}>
      <Icon name="left"/> Back to cohort companies
     </button>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Back to company list"><Icon name="close"/></button>
    </div>
    <div>
     <div>
      <p>Mature integration cohort · Company detail</p>
      <h2 id="adoption-company-title">{data?.company.name??"Company profile"}</h2>
     </div>
     <div className="rd-company-tags">
      {data?<><span>{data.company.integration_type}</span>
       {data.company.is_test?<span>Test</span>:null}
       <span>{data.stats.active_users} core-active users</span>
      </>:null}
     </div>
    </div>
   </header>
   <div className="rd-company-scroll">
    {loading?<div className="rd-loading">Loading company evidence…</div>:
     error||!data?<div className="rd-empty po-usage-error">
      <span>{error??"No company evidence available"}</span>
      <button type="button" onClick={()=>setRetry(x=>x+1)}>Try again</button>
      <button type="button" onClick={onClose}>Back to cohort</button>
     </div>:<>
      <div className="po-company-context">
       <strong>First 28 days after integration</strong>
       <span>{time(data.window.start)} to {time(data.window.end)}</span>
      </div>
      <div className="rd-health-strip po-company-health">
       <div><span>Independent core actions</span><strong>{nf.format(data.stats.core_actions)}</strong></div>
       <div><span>Active users</span><strong>{nf.format(data.stats.active_users)}</strong></div>
       <div><span>Core-active weeks</span><strong>{data.stats.active_weeks}/4</strong></div>
       <div><span>Qualifying sync events</span><strong>{nf.format(data.stats.sync_events)}</strong></div>
      </div>
      <div className="po-adoption-outcome-badges">
       {([
        ["7-day core adoption",data.outcomes.core_7d],
        ["28-day value conversion",data.outcomes.value_28d],
        ["28-day sustained adoption",data.outcomes.sustained_28d],
       ] as const).map(([label,yes])=><span key={label} className={yes?"is-met":"is-not-met"}>
        {label}: {yes?"Met":"Not met"}
       </span>)}
      </div>
      <div className="rd-status-tabs po-company-tabs">
       {([
        ["overview","Overview"],["activity","Activity"],["users","Users"],
       ] as const).map(([key,label])=>
        <button key={key} type="button" aria-pressed={tab===key} onClick={()=>setTab(key)}>{label}</button>)}
      </div>
      {tab==="overview"?<>
       <section className="rd-lifecycle-card">
        <div className="rd-section-title">
         <div><h3>Company lifecycle</h3><p>Observed milestones from integration through value</p></div>
        </div>
        <div className="rd-timeline">
         {milestones.map(([label,at],i)=>
          <div className={"rd-milestone"+(at?"":" is-empty")} key={label}>
           <span className="rd-dot"/>{i<4?<i/>:null}
           <small>{label}</small><strong title={time(at)}>{date(at)}</strong>
          </div>)}
        </div>
       </section>
       <div className="rd-detail-grid po-company-overview-grid">
        <section className="rd-detail-card">
         <div className="rd-section-title">
          <div><h3>Core actions by module</h3><p>Independent work in first 28 days</p></div>
         </div>
         <div className="po-company-module-list">
          {([
           ["ap","Bills / AP"],["ar","Invoices / AR"],["transactions","Transactions"],
          ] as const).map(([key,label])=><div key={key}>
           <span>{label}</span>
           <div className="po-company-module-track"><i style={{
            width:data.stats.core_actions?
             data.stats.modules[key]*100/data.stats.core_actions+"%":"0%",
           }}/></div>
           <strong>{nf.format(data.stats.modules[key])}</strong>
          </div>)}
         </div>
        </section>
        <section className="rd-detail-card">
         <div className="rd-section-title">
          <div><h3>Conversion evidence</h3>
           <p>Value requires a later-day independent core step</p></div>
         </div>
         <div className="po-company-context-list">
          <div><span>Core within 7 days</span><strong>{date(data.milestones.first_core_7d_at)}</strong></div>
          <div><span>Training sync</span><strong>{date(data.milestones.training_sync_at)}</strong></div>
          <div><span>Core after training</span><strong>{date(data.milestones.post_training_core_at)}</strong></div>
          <div><span>Closing sync / value</span><strong>{date(data.milestones.value_at)}</strong></div>
         </div>
        </section>
       </div>
      </>:null}
      {tab==="activity"?<>
       <section className="rd-weeks-card po-company-week-card">
        <div className="rd-section-title">
         <div><h3>First four integration-relative weeks</h3>
          <p>Week 1 starts at the successful integration timestamp</p></div>
        </div>
        <div className="rd-weeks-wrap">
         <table><thead><tr>
          <th>Period</th><th>Active users</th><th>Core actions</th>
          <th>AP</th><th>AR</th><th>Transactions</th><th>Syncs</th>
         </tr></thead><tbody>
          {data.weeks.map(w=><tr key={w.week}>
           <td><strong>Week {w.week}</strong> <span>{date(w.start)}</span></td>
           <td>{w.active_users}</td><td>{nf.format(w.core_actions)}</td>
           <td>{nf.format(w.modules.ap)}</td><td>{nf.format(w.modules.ar)}</td>
           <td>{nf.format(w.modules.transactions)}</td>
           <td>{nf.format(w.sync_events)}</td>
          </tr>)}
         </tbody></table>
        </div>
       </section>
       <section className="rd-weeks-card po-company-week-card">
        <div className="rd-section-title">
         <div><h3>Recent activity evidence</h3><p>Last 30 recorded qualifying events</p></div>
        </div>
        <div className="rd-weeks-wrap po-company-evidence">
         <table><thead><tr><th>Time</th><th>Event</th><th>Module</th><th>User</th></tr></thead>
          <tbody>{data.recent_events.map((e,i)=><tr key={e.at+":"+i}>
           <td>{time(e.at)}</td><td>{e.event}</td>
           <td>{e.module==="sync"?"Accounting Sync":e.module.toUpperCase()}</td>
           <td>{e.email}</td>
          </tr>)}</tbody>
         </table>
        </div>
       </section>
      </>:null}
      {tab==="users"?<section className="rd-weeks-card po-company-week-card">
       <div className="rd-section-title">
        <div><h3>Observed users</h3><p>Core work attributed to this company in its first 28 days</p></div>
       </div>
       <div className="rd-weeks-wrap po-company-member-table">
        <table><thead><tr>
         <th>User</th><th>Core actions</th><th>Active days</th>
         <th>AP</th><th>AR</th><th>Transactions</th><th>Last activity</th>
        </tr></thead><tbody>
         {data.users.map(u=><tr key={u.id}>
          <td><strong>{u.email}</strong></td>
          <td>{nf.format(u.core_actions)}</td><td>{nf.format(u.core_days)}</td>
          <td>{nf.format(u.modules.ap)}</td><td>{nf.format(u.modules.ar)}</td>
          <td>{nf.format(u.modules.transactions)}</td>
          <td>{time(u.last_core_at)}</td>
         </tr>)}
         {!data.users.length?<tr><td colSpan={7}>No qualifying activity attributed to a user.</td></tr>:null}
        </tbody></table>
       </div>
      </section>:null}
      <p className="po-company-freshness">
       Snapshot #{data.snapshot_id} · Source watermark {time(data.source_watermark_at)} ·
       Failed actions and automated/unclassified syncs never count as independent core work.
      </p>
     </>}
   </div>
  </section>
 </div>;
}
