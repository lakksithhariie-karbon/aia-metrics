"use client";

import { useEffect,useRef,useState } from "react";
import type {
 WorkflowSummary,WorkflowModule,WorkflowMask,WorkflowPeriod,
 WorkflowModuleUsers,WorkflowMixCompanies,WorkflowCompanyDetail,
 WorkflowModuleUser,WorkflowModuleCompany,WorkflowMixCompany,WorkflowCounts,
} from "../../lib/overview/workflow";

const nf=new Intl.NumberFormat("en-US");
const MODULE_LABELS:Record<WorkflowModule,string>={
 ap:"AP / Bills",ar:"AR / Invoices",transactions:"Transactions",
};
const PAGE_SIZE=8;
function Icon({name}:{name:"close"|"left"|"right"|"down"|"search"}){
 return <svg className="rd-icon" aria-hidden="true"><use href={"#i-"+name}/></svg>;
}
function when(at:string|null|undefined){
 if(!at)return "Not recorded";
 const d=new Date(at);
 if(!Number.isFinite(d.getTime()))return "Not recorded";
 return d.toLocaleString("en-GB",{
  timeZone:"Asia/Kolkata",day:"numeric",month:"short",year:"numeric",
  hour:"2-digit",minute:"2-digit",
 })+" IST";
}
function day(s:string|null|undefined){
 if(!s)return "—";
 const d=new Date(s.length===10?s+"T12:00:00Z":s);
 if(Number.isNaN(d.getTime()))return "—";
 return d.toLocaleDateString("en-GB",{
  timeZone:s.length===10?"UTC":"Asia/Kolkata",
  day:"numeric",month:"short",year:"numeric",
 });
}
function pages(page:number,total:number):Array<number|"…">{
 const values=[...new Set([1,page-1,page,page+1,total])]
  .filter(n=>n>0&&n<=total).sort((a,b)=>a-b);
 const result:Array<number|"…">=[];
 values.forEach((n,i)=>{
  if(i&&n-values[i-1]>1)result.push("…");
  result.push(n);
 });
 return result;
}
async function post<T>(body:Record<string,unknown>,signal:AbortSignal):Promise<T>{
 const r=await fetch("/api/overview-workflow",{
  method:"POST",headers:{"Content-Type":"application/json"},
  cache:"no-store",body:JSON.stringify(body),signal,
 });
 if(!r.ok)throw new Error(r.status===409||r.status===404
  ?"The published snapshot changed. Refresh the dashboard."
  :"Unable to load live workflow details. Try again.");
 return await r.json() as T;
}
export type WorkflowFocus =
 | {scope:"weekly";companyId:string;week:string;module:WorkflowModule;userId:string}
 | {scope:WorkflowPeriod;companyId:string;mask:WorkflowMask};

export function WorkflowModuleUsersModal({
 summary,week,module,expected,onClose,
}:{
 summary:WorkflowSummary;week:string;module:WorkflowModule;
 expected:number;onClose:()=>void;
}){
 const [query,setQuery]=useState("");
 const [deferred,setDeferred]=useState("");
 const [page,setPage]=useState(1);
 const [expanded,setExpanded]=useState<Set<string>>(new Set());
 const [data,setData]=useState<WorkflowModuleUsers|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const [focus,setFocus]=useState<WorkflowFocus|null>(null);
 const returnFocus=useRef<HTMLButtonElement|null>(null);
 const resultRef=useRef<HTMLDivElement>(null);
 const cache=useRef<Map<string,WorkflowModuleUsers>>(new Map());
 useEffect(()=>{
  const timer=setTimeout(()=>setDeferred(query),250);
  return ()=>clearTimeout(timer);
 },[query]);
 useEffect(()=>{
  setPage(1);setExpanded(new Set());
  resultRef.current?.scrollTo({top:0});
 },[deferred]);
 const key=[summary.snapshotId,week,module,deferred,page].join("|");
 useEffect(()=>{
  const controller=new AbortController();
  const saved=cache.current.get(key);
  if(saved){setData(saved);setLoading(false);setError(null);return ()=>controller.abort()}
  setData(null);setLoading(true);setError(null);
  post<WorkflowModuleUsers>({
   action:"module_users",snapshot_id:summary.snapshotId,week,module,
   query:deferred,page,page_size:PAGE_SIZE,
  },controller.signal).then(result=>{
   if(controller.signal.aborted)return;
   if(result.contract!=="independent_workflow_module_users_v1"
    ||result.snapshot_id!==summary.snapshotId
    ||result.week_start!==week||result.module!==module
    ||result.segment_total!==expected)
    throw new Error("The selected point does not reconcile with its users. Refresh.");
   cache.current.set(key,result);setData(result);
  }).catch(e=>{
   if(!controller.signal.aborted)setError(e instanceof Error?e.message:"No data");
  }).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return ()=>controller.abort();
 },[key,summary.snapshotId,week,module,deferred,page,retry,expected]);
 useEffect(()=>{
  const prior=document.body.style.overflow;document.body.style.overflow="hidden";
  return ()=>{document.body.style.overflow=prior};
 },[]);
 useEffect(()=>{
  const onKey=(e:KeyboardEvent)=>{
   if(e.key!=="Escape")return;
   e.preventDefault();if(focus)setFocus(null);else onClose();
  };
  window.addEventListener("keydown",onKey);
  return ()=>window.removeEventListener("keydown",onKey);
 },[onClose,focus]);
 function toggle(id:string){
  setExpanded(prev=>prev.has(id)?new Set():new Set([id]));
 }
 function open(user:WorkflowModuleUser,company:WorkflowModuleCompany,button:HTMLButtonElement){
  returnFocus.current=button;
  setFocus({scope:"weekly",companyId:company.id,week,module,userId:user.id});
 }
 const totalPages=Math.max(1,Math.ceil((data?.total??0)/PAGE_SIZE));
 const from=data?.rows.length?(page-1)*PAGE_SIZE+1:0;
 const to=data?.rows.length?from+data.rows.length-1:0;
 return <>
  <div className="rd-overlay" role="presentation">
   <section className="rd-modal rd-activation-modal po-workflow-list-modal"
    role="dialog" aria-modal="true" aria-labelledby="po-workflow-module-title">
    <header className="rd-modal-head">
     <div>
      <p>Product Overview · Module usage over time</p>
      <h2 id="po-workflow-module-title">{MODULE_LABELS[module]}</h2>
      <span>{nf.format(expected)} unique users · Week starting {day(week)}</span>
     </div>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Close module users"><Icon name="close"/></button>
    </header>
    <div className="po-workflow-modal-summary">
     <div><span>Selected module</span><strong>{MODULE_LABELS[module]}</strong></div>
     <div><span>Distinct users</span><strong>{nf.format(expected)}</strong></div>
     <div><span>Completed week</span><strong>{day(week)}</strong></div>
    </div>
    <div className="rd-drill-toolbar po-workflow-drill-toolbar">
     <span className="po-workflow-static-tab">{MODULE_LABELS[module]} · {nf.format(expected)} users</span>
     <div className="rd-search">
      <Icon name="search"/>
      <input value={query} aria-label="Search users or companies"
       onChange={e=>setQuery(e.currentTarget.value)}
       placeholder="Search users or companies"/>
      {query?<button type="button" onClick={()=>setQuery("")}
       aria-label="Clear search"><Icon name="close"/></button>:null}
     </div>
    </div>
    <div className="rd-table-wrap po-workflow-table-wrap" ref={resultRef}>
     {loading?<div className="rd-loading">Loading module-active users…</div>
     :error?<div className="rd-empty po-usage-error">
      <span>{error}</span><button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
     </div>
     :!data?<div className="rd-empty">No data available.</div>
     :<table className="rd-activation-table po-workflow-user-table">
      <thead><tr>
       <th scope="col"><span className="sr-only">Expand user</span></th>
       <th scope="col">User / Company</th>
       <th scope="col">Companies</th>
       <th scope="col">Module actions</th>
       <th scope="col">Active days</th>
       <th scope="col">Last active</th>
      </tr></thead>
      <tbody>
       {data.rows.length?data.rows.flatMap(user=>{
        const openRow=expanded.has(user.id);
        const parent=<tr key={"user:"+user.id} className={openRow?"is-expanded":""}>
         <td><button className="rd-expander" type="button" aria-expanded={openRow}
          aria-label={(openRow?"Collapse ":"Expand ")+user.email}
          onClick={()=>toggle(user.id)}><Icon name={openRow?"down":"right"}/></button></td>
         <td><button type="button" className="rd-company-link" onClick={()=>toggle(user.id)}>
          <strong>{user.email}</strong><span>Distinct user · Click to show companies</span>
         </button></td>
         <td>{nf.format(user.companies_count)}</td>
         <td className="has-value">{nf.format(user.actions)}</td>
         <td>{nf.format(user.active_days)}</td>
         <td>{when(user.last_active_at)}</td>
        </tr>;
        if(!openRow)return [parent];
        return [parent,...user.companies.map(c=><tr className="rd-user-row po-workflow-nested" key={"company:"+user.id+":"+c.id}>
         <td/>
         <td><span className="rd-user-indent">
          <button type="button" className="po-workflow-nested-link"
           onClick={e=>open(user,c,e.currentTarget)}>
           {c.name}<small>View full company activity →</small>
          </button>
         </span></td>
         <td>{c.is_test?"Test":"Company"}</td>
         <td>{nf.format(c.actions)}</td>
         <td>{nf.format(c.active_days)}</td>
         <td>{when(c.last_active_at)}</td>
        </tr>)];
       }):<tr><td colSpan={6}><div className="rd-empty">No matching users.</div></td></tr>}
      </tbody>
     </table>}
    </div>
    <footer className="rd-modal-foot rd-modal-foot-paginated">
     <div className="rd-table-summary">
      <span>Unique users · Qualifying independent {MODULE_LABELS[module]} work</span>
      <small>{data?"Showing "+from+"–"+to+" of "+nf.format(data.total):
       "Snapshot #"+summary.snapshotId}</small>
     </div>
     {data&&totalPages>1?<nav className="rd-pagination" aria-label="User pages">
      <button type="button" disabled={page<=1} aria-label="Previous page"
       onClick={()=>setPage(n=>n-1)}><Icon name="left"/></button>
      {pages(page,totalPages).map((p,i)=>p==="…"
       ?<span key={"dots:"+i} className="rd-page-ellipsis">…</span>
       :<button key={p} type="button" aria-current={page===p?"page":undefined}
        onClick={()=>setPage(p)}>{p}</button>)}
      <button type="button" disabled={page>=totalPages} aria-label="Next page"
       onClick={()=>setPage(n=>n+1)}><Icon name="right"/></button>
     </nav>:null}
    </footer>
   </section>
  </div>
  {focus?<WorkflowCompanyModal summary={summary} focus={focus}
   onClose={()=>{
    setFocus(null);
    requestAnimationFrame(()=>returnFocus.current?.focus({preventScroll:true}));
   }}/>:null}
 </>;
}

export function WorkflowMixCompaniesModal({
 summary,mask,label,onClose,
}:{
 summary:WorkflowSummary;mask:WorkflowMask;label:string;onClose:()=>void;
}){
 const matchedRow=summary.mix.rows.find(x=>x.mask===mask);
 const [period,setPeriod]=useState<WorkflowPeriod>("current");
 const [query,setQuery]=useState("");
 const [deferred,setDeferred]=useState("");
 const [page,setPage]=useState(1);
 const [expanded,setExpanded]=useState<string|null>(null);
 const [focus,setFocus]=useState<WorkflowFocus|null>(null);
 const [data,setData]=useState<WorkflowMixCompanies|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const returnFocus=useRef<HTMLButtonElement|null>(null);
 const scroll=useRef<HTMLDivElement>(null);
 const cache=useRef<Map<string,WorkflowMixCompanies>>(new Map());
 useEffect(()=>{
  const t=setTimeout(()=>setDeferred(query),250);
  return ()=>clearTimeout(t);
 },[query]);
 useEffect(()=>{
  setPage(1);setExpanded(null);scroll.current?.scrollTo({top:0});
 },[period,deferred]);
 const key=[summary.snapshotId,mask,period,deferred,page].join("|");
 useEffect(()=>{
  const controller=new AbortController();
  const cached=cache.current.get(key);
  if(cached){setData(cached);setLoading(false);setError(null);return ()=>controller.abort()}
  setData(null);setLoading(true);setError(null);
  post<WorkflowMixCompanies>({
   action:"mix_companies",snapshot_id:summary.snapshotId,
   mask,period,query:deferred,page,page_size:PAGE_SIZE,
  },controller.signal).then(result=>{
   if(controller.signal.aborted)return;
   const expected=period==="current"?matchedRow?.current:matchedRow?.previous;
   if(result.contract!=="independent_workflow_mix_companies_v1"
    ||result.snapshot_id!==summary.snapshotId||result.mask!==mask
    ||result.period!==period||expected===undefined||result.segment_total!==expected)
    throw new Error("Companies no longer reconcile with this chart. Refresh.");
   cache.current.set(key,result);setData(result);
  }).catch(e=>{if(!controller.signal.aborted)
   setError(e instanceof Error?e.message:"No data");
  }).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return ()=>controller.abort();
 },[key,summary.snapshotId,mask,period,deferred,page,retry,matchedRow?.current,matchedRow?.previous]);
 useEffect(()=>{
  const old=document.body.style.overflow;document.body.style.overflow="hidden";
  return ()=>{document.body.style.overflow=old};
 },[]);
 useEffect(()=>{
  const onKey=(e:KeyboardEvent)=>{
   if(e.key!=="Escape")return;
   e.preventDefault();if(focus)setFocus(null);else onClose();
  };
  window.addEventListener("keydown",onKey);
  return ()=>window.removeEventListener("keydown",onKey);
 },[onClose,focus]);
 function openCompany(c:WorkflowMixCompany,btn:HTMLButtonElement){
  returnFocus.current=btn;
  setFocus({scope:period,companyId:c.id,mask});
 }
 const expected=period==="current"?matchedRow?.current??0:matchedRow?.previous??0;
 const totalPages=Math.max(1,Math.ceil((data?.total??0)/PAGE_SIZE));
 const from=data?.rows.length?(page-1)*PAGE_SIZE+1:0;
 const to=data?.rows.length?from+data.rows.length-1:0;
 return <>
  <div className="rd-overlay" role="presentation">
   <section className="rd-modal rd-activation-modal po-workflow-list-modal"
    role="dialog" aria-modal="true" aria-labelledby="po-workflow-mix-title">
    <header className="rd-modal-head">
     <div>
      <p>Product Overview · Module combinations</p>
      <h2 id="po-workflow-mix-title">{label}</h2>
      <span>{nf.format(expected)} companies · {period==="current"?"Latest":"Previous"} rolling 28 days</span>
     </div>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Close company combinations"><Icon name="close"/></button>
    </header>
    <div className="po-workflow-modal-summary">
     <div><span>Current population</span><strong>{nf.format(matchedRow?.current??0)}</strong></div>
     <div><span>Previous population</span><strong>{nf.format(matchedRow?.previous??0)}</strong></div>
     <div><span>Category</span><strong>{label}</strong></div>
    </div>
    <div className="rd-drill-toolbar po-workflow-drill-toolbar">
     <div className="rd-status-tabs" aria-label="Comparison period">
      {(["current","previous"] as const).map(p=><button
       type="button" key={p} aria-pressed={p===period} onClick={()=>setPeriod(p)}>
       {p==="current"?"Current 28 days":"Previous 28 days"}
       <span>{nf.format(p==="current"?matchedRow?.current??0:matchedRow?.previous??0)}</span>
      </button>)}
     </div>
     <div className="rd-search">
      <Icon name="search"/>
      <input value={query} aria-label="Search companies"
       onChange={e=>setQuery(e.currentTarget.value)} placeholder="Search companies"/>
      {query?<button type="button" onClick={()=>setQuery("")}
       aria-label="Clear search"><Icon name="close"/></button>:null}
     </div>
    </div>
    <div className="rd-table-wrap po-workflow-table-wrap" ref={scroll}>
     {loading?<div className="rd-loading">Loading companies…</div>
     :error?<div className="rd-empty po-usage-error">
      <span>{error}</span><button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
     </div>
     :!data?<div className="rd-empty">No data available.</div>
     :<table className="rd-activation-table po-workflow-mix-table">
      <thead><tr>
       <th scope="col"><span className="sr-only">Expand</span></th>
       <th scope="col">Company</th>
       <th scope="col">Users</th>
       <th scope="col">Core actions</th>
       <th scope="col">Active days</th>
       <th scope="col">AP</th>
       <th scope="col">AR</th>
       <th scope="col">Transactions</th>
       <th scope="col">Last active</th>
      </tr></thead>
      <tbody>
       {data.rows.length?data.rows.flatMap(c=>{
        const opened=expanded===c.id;
        const parent=<tr key={"company:"+c.id} className={opened?"is-expanded":""}>
         <td><button type="button" className="rd-expander" aria-expanded={opened}
          aria-label={(opened?"Collapse ":"Expand ")+c.name}
          onClick={()=>setExpanded(opened?null:c.id)}>
          <Icon name={opened?"down":"right"}/></button></td>
         <td><button type="button" className="rd-company-link"
          onClick={e=>openCompany(c,e.currentTarget)}>
          <strong>{c.name}</strong><span>{c.is_test?"Test · ":""}View full company profile</span>
         </button></td>
         <td>{nf.format(c.users)}</td>
         <td className="has-value">{nf.format(c.actions)}</td>
         <td>{nf.format(c.active_days)}</td>
         <td>{nf.format(c.modules.ap)}</td>
         <td>{nf.format(c.modules.ar)}</td>
         <td>{nf.format(c.modules.transactions)}</td>
         <td>{when(c.last_active_at)}</td>
        </tr>;
        if(!opened)return [parent];
        return [parent,<tr className="rd-user-row" key={"users:"+c.id}>
         <td/>
         <td colSpan={8}>
          <WorkflowInlineCompanyUsers summary={summary}
           focus={{scope:period,companyId:c.id,mask}}
           onOpen={button=>openCompany(c,button)}/>
         </td>
        </tr>];
       }):<tr><td colSpan={9}><div className="rd-empty">No matching companies.</div></td></tr>}
      </tbody>
     </table>}
    </div>
    <footer className="rd-modal-foot rd-modal-foot-paginated">
     <div className="rd-table-summary">
      <span>Distinct companies · Exactly one combination per period</span>
      <small>{data?"Showing "+from+"–"+to+" of "+nf.format(data.total):
       "Snapshot #"+summary.snapshotId}</small>
     </div>
     {data&&totalPages>1?<nav className="rd-pagination" aria-label="Company pages">
      <button type="button" disabled={page<=1} aria-label="Previous page"
       onClick={()=>setPage(n=>n-1)}><Icon name="left"/></button>
      {pages(page,totalPages).map((n,i)=>n==="…"
       ?<span key={"dots:"+i} className="rd-page-ellipsis">…</span>
       :<button key={n} type="button" aria-current={page===n?"page":undefined}
        onClick={()=>setPage(n)}>{n}</button>)}
      <button type="button" disabled={page>=totalPages}
       aria-label="Next page" onClick={()=>setPage(n=>n+1)}><Icon name="right"/></button>
     </nav>:null}
    </footer>
   </section>
  </div>
  {focus?<WorkflowCompanyModal summary={summary} focus={focus}
   onClose={()=>{
    setFocus(null);
    requestAnimationFrame(()=>returnFocus.current?.focus({preventScroll:true}));
   }}/>:null}
 </>;
}

function WorkflowInlineCompanyUsers({
 summary,focus,onOpen,
}:{
 summary:WorkflowSummary;focus:WorkflowFocus;
 onOpen:(button:HTMLButtonElement)=>void;
}){
 const [details,setDetails]=useState<WorkflowCompanyDetail|null>(null);
 const [error,setError]=useState<string|null>(null);
 useEffect(()=>{
  const controller=new AbortController();
  post<WorkflowCompanyDetail>({
   action:"company",snapshot_id:summary.snapshotId,
   company_id:focus.companyId,scope:focus.scope,
   ...(focus.scope==="weekly"
    ?{week:focus.week,module:focus.module,user_id:focus.userId}
    :{mask:focus.mask}),
  },controller.signal).then(result=>{
   if(!controller.signal.aborted)setDetails(result);
  }).catch(e=>{
   if(!controller.signal.aborted)setError(e instanceof Error?e.message:"Unavailable");
  });
  return ()=>controller.abort();
 },[summary.snapshotId,focus.companyId,focus.scope,
  focus.scope==="weekly"?focus.week:"",
  focus.scope==="weekly"?focus.userId:"",
  focus.scope==="weekly"?focus.module:"",
  focus.scope!=="weekly"?focus.mask:""]);
 if(error)return <span className="po-workflow-inline-note">{error}</span>;
 if(!details)return <span className="po-workflow-inline-note">Loading company users…</span>;
 return <div className="po-workflow-inline-users">
  <span>Users active in this company:</span>
  {details.users.map(u=><span key={u.id}>
   <strong>{u.email}</strong> · {nf.format(u.core_actions)} core actions
  </span>)}
  <button type="button" onClick={e=>onOpen(e.currentTarget)}>View full breakdown →</button>
 </div>;
}

export function WorkflowCompanyModal({
 summary,focus,onClose,
}:{
 summary:WorkflowSummary;focus:WorkflowFocus;onClose:()=>void;
}){
 const [details,setDetails]=useState<WorkflowCompanyDetail|null>(null);
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState<string|null>(null);
 const [retry,setRetry]=useState(0);
 const [tab,setTab]=useState<"overview"|"activity"|"users">("overview");
 useEffect(()=>{
  const controller=new AbortController();
  setDetails(null);setError(null);setLoading(true);
  post<WorkflowCompanyDetail>({
   action:"company",snapshot_id:summary.snapshotId,
   company_id:focus.companyId,scope:focus.scope,
   ...(focus.scope==="weekly"
    ?{week:focus.week,module:focus.module,user_id:focus.userId}
    :{mask:focus.mask}),
  },controller.signal).then(result=>{
   if(controller.signal.aborted)return;
   if(result.contract!=="independent_workflow_company_v1"
    ||result.snapshot_id!==summary.snapshotId
    ||result.company.id!==focus.companyId)throw new Error("Company snapshot mismatch");
   setDetails(result);
  }).catch(e=>{
   if(!controller.signal.aborted)setError(e instanceof Error?e.message:"Unavailable");
  }).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return ()=>controller.abort();
 },[summary.snapshotId,focus.companyId,focus.scope,
  focus.scope==="weekly"?focus.week:"",
  focus.scope==="weekly"?focus.module:"",
  focus.scope==="weekly"?focus.userId:"",
  focus.scope!=="weekly"?focus.mask:"",
  retry]);
 return <div className="rd-overlay rd-overlay-level-2" role="presentation">
  <section className="rd-modal rd-company-modal po-workflow-company-modal"
   role="dialog" aria-modal="true" aria-labelledby="po-workflow-company-title">
   <header className="rd-company-head">
    <div className="rd-company-topline">
     <button type="button" className="rd-back" onClick={onClose}>
      <Icon name="left"/> Back to workflow breakdown
     </button>
     <button type="button" className="rd-close" onClick={onClose}
      aria-label="Back to workflow companies"><Icon name="close"/></button>
    </div>
    <div>
     <div><p>Company activity profile · Workflow Usage</p>
      <h2 id="po-workflow-company-title">{details?.company.name??"Company profile"}</h2>
     </div>
     <div className="rd-company-tags">
      <span>{focus.scope==="weekly"?"Selected completed week":
       focus.scope==="current"?"Current 28 days":"Previous 28 days"}</span>
      {details?.company.is_test?<span>Test</span>:null}
      {details?<span>{nf.format(details.stats.active_users)} active users</span>:null}
     </div>
    </div>
   </header>
   <div className="rd-company-scroll">
    {loading?<div className="rd-loading">Loading company activity…</div>
    :error||!details?<div className="rd-empty po-usage-error">
     <span>{error??"No company data available"}</span>
     <button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
     <button type="button" onClick={onClose}>Back to companies</button>
    </div>:<>
     <div className="po-company-context">
      <strong>Selected reporting window</strong>
      <span>{when(details.window.start)} to {when(details.window.end)}</span>
      <small>Company-wide independent work across all modules</small>
     </div>
     <div className="rd-health-strip po-company-health">
      <div><span>Core actions</span><strong>{nf.format(details.stats.core_actions)}</strong></div>
      <div><span>Active users</span><strong>{nf.format(details.stats.active_users)}</strong></div>
      <div><span>Active days</span><strong>{nf.format(details.stats.active_days)}</strong></div>
      <div><span>Last core work</span><strong className="po-company-date">{when(details.stats.last_activity_at)}</strong></div>
     </div>
     <div className="rd-status-tabs po-company-tabs">
      {(["overview","activity","users"] as const).map(key=>
       <button key={key} type="button" aria-pressed={tab===key}
        onClick={()=>setTab(key)}>{key[0].toUpperCase()+key.slice(1)}</button>)}
     </div>
     {tab==="overview"?<>
      <section className="rd-lifecycle-card">
       <div className="rd-section-title"><div>
        <h3>Company context</h3>
        <p>Historical milestones are shown only when recorded</p>
       </div></div>
       <div className="rd-timeline">
        {([
         ["Company created",details.milestones.company_created_at],
         ["Integration recorded",details.milestones.integration_at],
         ["First work in window",details.stats.first_activity_at],
         ["Last work in window",details.stats.last_activity_at],
         ["Last qualifying sync",details.milestones.last_qualifying_sync_at],
        ] as const).map(([label,at],i)=><div key={label}
         className={"rd-milestone "+(!at?"is-empty":"")}>
         <span className="rd-dot"/>{i<4?<i/>:null}
         <small>{label}</small><strong title={when(at)}>{day(at)}</strong>
        </div>)}
       </div>
      </section>
      <div className="rd-detail-grid po-company-overview-grid">
       <section className="rd-detail-card">
        <div className="rd-section-title"><div>
         <h3>Core actions by module</h3><p>Across this company's selected reporting period</p>
        </div></div>
        <div className="po-company-module-list">
         {(["ap","ar","transactions"] as const).map(key=><div key={key}>
          <span>{MODULE_LABELS[key]}</span>
          <div className="po-company-module-track"><i style={{
           width:details.stats.core_actions?
            details.stats.modules[key]*100/details.stats.core_actions+"%":"0%",
          }}/></div>
          <strong>{nf.format(details.stats.modules[key])}</strong>
         </div>)}
        </div>
       </section>
       <section className="rd-detail-card">
        <div className="rd-section-title"><div>
         <h3>Activity evidence</h3><p>Distinct users and observed actions</p>
        </div></div>
        <div className="po-company-context-list">
         <div><span>Window start</span><strong>{when(details.window.start)}</strong></div>
         <div><span>Window end</span><strong>{when(details.window.end)}</strong></div>
         <div><span>Observed users</span><strong>{nf.format(details.stats.active_users)}</strong></div>
         {focus.scope==="weekly"?<div><span>Selected user, {MODULE_LABELS[focus.module]}</span>
          <strong>{nf.format(
           details.users.find(u=>u.id===focus.userId)?.modules[focus.module]??0,
          )} module actions</strong>
         </div>:null}
        </div>
       </section>
      </div>
     </>:null}
     {tab==="activity"?<>
      <section className="rd-weeks-card po-company-week-card">
       <div className="rd-section-title"><div>
        <h3>Weekly workflow activity</h3>
        <p>IST calendar weeks overlapping the selected period</p>
       </div></div>
       <div className="rd-weeks-wrap">
        <table><thead><tr>
         <th>Week</th><th>Users</th><th>Actions</th><th>AP</th><th>AR</th><th>Transactions</th>
        </tr></thead><tbody>
         {details.weeks.map(w=><tr key={w.week_start}>
          <td>{day(w.week_start)}</td><td>{nf.format(w.active_users)}</td>
          <td>{nf.format(w.core_actions)}</td><td>{nf.format(w.modules.ap)}</td>
          <td>{nf.format(w.modules.ar)}</td><td>{nf.format(w.modules.transactions)}</td>
         </tr>)}
        </tbody></table>
       </div>
      </section>
      <section className="rd-weeks-card po-company-week-card">
       <div className="rd-section-title"><div>
        <h3>Recent event evidence</h3><p>Last 30 qualifying actions within this window</p>
       </div></div>
       <div className="rd-weeks-wrap po-company-evidence">
        <table><thead><tr><th>When</th><th>Event</th><th>Module</th><th>User</th></tr></thead>
         <tbody>{details.recent_events.map((e,i)=><tr key={e.at+":"+i}>
          <td>{when(e.at)}</td><td>{e.event}</td>
          <td>{MODULE_LABELS[e.module]}</td>
          <td>{e.email}</td>
         </tr>)}</tbody>
        </table>
       </div>
      </section>
     </>:null}
     {tab==="users"?<section className="rd-weeks-card po-company-week-card">
      <div className="rd-section-title"><div>
       <h3>Active users</h3><p>Each user counted once in this company</p>
      </div></div>
      <div className="rd-weeks-wrap po-company-member-table">
       <table><thead><tr>
        <th>User</th><th>Core actions</th><th>Active days</th>
        <th>AP</th><th>AR</th><th>Transactions</th><th>Last active</th>
       </tr></thead><tbody>
        {details.users.map(u=><tr key={u.id}
         className={focus.scope==="weekly"&&u.id===focus.userId?"po-focused-row":""}>
         <td><strong>{u.email}</strong></td>
         <td>{nf.format(u.core_actions)}</td><td>{nf.format(u.active_days)}</td>
         <td>{nf.format(u.modules.ap)}</td><td>{nf.format(u.modules.ar)}</td>
         <td>{nf.format(u.modules.transactions)}</td><td>{when(u.last_active_at)}</td>
        </tr>)}
       </tbody></table>
      </div>
     </section>:null}
     <p className="po-company-freshness">Snapshot #{details.snapshot_id} ·
      Source watermark {when(details.source_watermark_at)} ·
      Accounting Sync excluded from independent core activity.</p>
    </>}
   </div>
  </section>
 </div>;
}
