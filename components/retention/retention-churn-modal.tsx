"use client";

import React, { useEffect, useState } from "react";
import type { RetentionChurnSeriesRow } from "../../lib/retention/types";
import type {
  RetentionChurnCompanyRow,
  RetentionChurnDrillResponse,
  RetentionChurnSegment,
} from "../../lib/retention/drill-types";

const nf = new Intl.NumberFormat("en-US");

function Icon({ name }: { name: "left"|"right"|"down"|"close"|"search" }) {
  const paths = {
    left:"m14 6-6 6 6 6", right:"m10 6 6 6-6 6", down:"m7 10 5 5 5-5",
    close:"m6 6 12 12M18 6 6 18",
    search:"M21 21l-4.35-4.35m1.35-5.65a7 7 0 1 1-14 0 7 7 0 0 1 14 0Z",
  };
  return <svg className="rd-icon" viewBox="0 0 24 24" aria-hidden="true"><path d={paths[name]} /></svg>;
}

function monthLabel(month:string){
  return new Date(month+"-01T12:00:00Z").toLocaleDateString("en-GB",{month:"short",year:"numeric",timeZone:"UTC"}).replace("Sept","Sep");
}

function paginationItems(current:number,total:number):Array<number|"ellipsis">{
  if(total<=7)return Array.from({length:total},(_,i)=>i+1);
  if(current<=4)return [1,2,3,4,5,"ellipsis",total];
  if(current>=total-3)return [1,"ellipsis",total-4,total-3,total-2,total-1,total];
  return [1,"ellipsis",current-1,current,current+1,"ellipsis",total];
}

const cache=new Map<string,RetentionChurnDrillResponse>();
function key(month:string,segment:string,query:string,page:number){
  return [month,segment,query.trim().toLowerCase(),page].join("|");
}
async function fetchDrill(args:{month:string;segment:RetentionChurnSegment;query:string;page:number;signal?:AbortSignal}){
  const k=key(args.month,args.segment,args.query,args.page);
  const hit=cache.get(k); if(hit)return hit;
  const response=await fetch("/api/retention-drill",{method:"POST",headers:{"Content-Type":"application/json"},signal:args.signal,body:JSON.stringify({
    action:"churn_month",month:args.month,segment:args.segment,query:args.query,page:args.page,page_size:8
  })});
  const payload=await response.json().catch(()=>({}));
  if(!response.ok)throw new Error(payload?.error??"retention_churn_unavailable");
  cache.set(k,payload as RetentionChurnDrillResponse);
  return payload as RetentionChurnDrillResponse;
}
function prefetch(args:{month:string;segment:RetentionChurnSegment;query:string;page:number}){
  if(cache.has(key(args.month,args.segment,args.query,args.page)))return;
  void fetchDrill(args).catch(()=>undefined);
}

export default function RetentionChurnModal({
  month,initialSegment="all",onClose,onCompany,onPrefetchCompany,
}:{
  month:RetentionChurnSeriesRow;
  initialSegment?:RetentionChurnSegment;
  onClose:()=>void;
  onCompany:(company:RetentionChurnCompanyRow)=>void;
  onPrefetchCompany?:(id:string)=>void;
}){
  const [segment,setSegment]=useState<RetentionChurnSegment>(initialSegment);
  const [query,setQuery]=useState("");
  const [deferredQuery,setDeferredQuery]=useState("");
  const [page,setPage]=useState(1);
  const [expanded,setExpanded]=useState<Set<string>>(new Set());
  const [data,setData]=useState<RetentionChurnDrillResponse|null>(null);
  const [loading,setLoading]=useState(true);

  useEffect(()=>{const t=setTimeout(()=>setDeferredQuery(query),250);return()=>clearTimeout(t)},[query]);
  useEffect(()=>{
    setSegment(initialSegment);
    setPage(1);
    setExpanded(new Set());
  },[initialSegment,month.month]);
  useEffect(()=>{setPage(1);setExpanded(new Set())},[segment,deferredQuery]);
  useEffect(()=>{
    const controller=new AbortController();
    const args={month:month.month,segment,query:deferredQuery,page};
    const hit=cache.get(key(args.month,args.segment,args.query,args.page));
    if(hit){setData(hit);setLoading(false);const pc=Math.max(1,Math.ceil(hit.total/hit.page_size));if(page>1)prefetch({...args,page:page-1});if(page<pc)prefetch({...args,page:page+1});return()=>controller.abort()}
    setLoading(true);
    fetchDrill({...args,signal:controller.signal}).then(result=>{
      if(controller.signal.aborted)return;setData(result);
      const pc=Math.max(1,Math.ceil(result.total/result.page_size));
      if(result.page>1)prefetch({...args,page:result.page-1});
      if(result.page<pc)prefetch({...args,page:result.page+1});
    }).catch(()=>{if(!controller.signal.aborted)setData(null)}).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
    return()=>controller.abort();
  },[month.month,segment,deferredQuery,page]);

  const counts=data?.counts??{
    all:month.eligible,
    active:month.active,
    churned:month.churned,
    entered:month.entered,
    reactivated:month.reactivated,
  };
  const pageCount=Math.max(1,Math.ceil((data?.total??0)/(data?.page_size??8)));
  const safePage=data?.page??page;
  const toggle=(id:string)=>setExpanded(current=>current.has(id)?new Set():new Set([id]));

  return <div className="rd-overlay" role="presentation">
    <section className="rd-modal rd-activation-modal rd-churn-month-modal" role="dialog" aria-modal="true" aria-labelledby="churn-month-title">
      <header className="rd-modal-head">
        <div>
          <p>Monthly churn · {monthLabel(month.month)}</p>
          <h2 id="churn-month-title">{month.rate_pct?.toFixed(1)??"—"}% · {nf.format(month.churned)} churned</h2>
          <span>{nf.format(month.eligible)} eligible companies · {nf.format(month.active)} active in month</span>
        </div>
        <button type="button" className="rd-close" onClick={onClose} aria-label="Close monthly churn drill"><Icon name="close"/></button>
      </header>

      <div className="rd-drill-toolbar">
        <div className="rd-status-tabs" role="tablist" aria-label="Monthly churn segment">
          {([
            ["all","All",counts.all],
            ["churned","Churned",counts.churned],
            ["active","Active",counts.active],
            ["entered","Entered churn",counts.entered],
            ["reactivated","Reactivated",counts.reactivated],
          ] as const).map(([k,label,count])=>
            <button type="button" key={k} aria-pressed={segment===k} onClick={()=>setSegment(k)}>{label}<span>{nf.format(count)}</span></button>
          )}
        </div>
        <div className="rd-search"><Icon name="search"/><input value={query} onChange={e=>setQuery(e.currentTarget.value)} placeholder="Search companies or users" aria-label="Search companies or users"/>{query?<button type="button" onClick={()=>setQuery("")} aria-label="Clear search"><Icon name="close"/></button>:null}</div>
      </div>

      <div className="rd-table-wrap">
        {loading&&!data?<div className="rd-loading">Loading monthly churn companies…</div>:!data?<div className="rd-empty">Couldn’t load this churn month.</div>:
        <table className="rd-activation-table rd-churn-month-table">
          <thead><tr><th><span className="sr-only">Expand users</span></th><th>Company / user</th><th>Status</th><th>Users</th><th>Core</th><th>AP</th><th>AR</th><th>Transaction</th><th>GST</th><th>Sync</th></tr></thead>
          <tbody>{data.rows.length?data.rows.flatMap(company=>{
            const open=expanded.has(company.id);
            const parent=<tr key={company.id} className={open?"is-expanded":""}>
              <td><button type="button" className="rd-expander" onClick={()=>toggle(company.id)} aria-label={(open?"Collapse ":"Expand ")+company.name}><Icon name={open?"down":"right"}/></button></td>
              <td><button type="button" className="rd-company-link" onMouseEnter={()=>onPrefetchCompany?.(company.id)} onFocus={()=>onPrefetchCompany?.(company.id)} onClick={()=>onCompany(company)}><strong>{company.name}</strong><span>{company.integration}{company.is_test?" · Test":""}</span></button></td>
              <td>
                <span
                  className={
                    "rd-status " +
                    (company.reactivated
                      ? "reactivated"
                      : company.entered
                        ? "entered"
                        : company.active
                          ? "activated"
                          : "no_training")
                  }
                >
                  {company.reactivated
                    ? "Reactivated"
                    : company.entered
                      ? "Entered churn"
                      : company.active
                        ? "Active"
                        : "Churned"}
                </span>
              </td>
              <td>{company.active_users}/{company.observed_users}</td>
              <td className={company.core_events?"has-value":""}>{nf.format(company.core_events)}</td>
              <td className={company.totals.ap?"has-value":""}>{nf.format(company.totals.ap)}</td>
              <td className={company.totals.ar?"has-value":""}>{nf.format(company.totals.ar)}</td>
              <td className={company.totals.transactions?"has-value":""}>{nf.format(company.totals.transactions)}</td>
              <td className={company.totals.gst?"has-value":""}>{nf.format(company.totals.gst)}</td>
              <td className={company.totals.sync?"has-value":""}>{nf.format(company.totals.sync)}</td>
            </tr>;
            if(!open)return [parent];
            const visible=company.users.slice(0,5);
            const children=visible.map(user=><tr className="rd-user-row" key={company.id+"-"+user.id}>
              <td/><td><span className="rd-user-indent">{user.email}</span></td>
              <td><span className={"rd-status "+(user.active?"activated":"")}>{user.active?"Active":"No activity"}</span></td>
              <td/><td>{nf.format(user.core_events)}</td><td>{nf.format(user.totals.ap)}</td><td>{nf.format(user.totals.ar)}</td><td>{nf.format(user.totals.transactions)}</td><td>{nf.format(user.totals.gst)}</td><td>{nf.format(user.totals.sync)}</td>
            </tr>);
            if(company.users.length>visible.length)children.push(<tr className="rd-user-row rd-more-users-row" key={company.id+"-more"}><td/><td colSpan={9}><button type="button" onClick={()=>onCompany(company)}>+{company.users.length-visible.length} more users · View company profile</button></td></tr>);
            return [parent,...children];
          }):<tr><td colSpan={10}><div className="rd-empty">No matching companies.</div></td></tr>}</tbody>
        </table>}
      </div>

      <footer className="rd-modal-foot rd-modal-foot-paginated">
        <div className="rd-table-summary">
          <span>
            Company slices are All / Churned / Active / Entered churn / Reactivated.
            User rows remain active or inactive within the selected month.
          </span>
          <small>{data?nf.format(data.total)+" matching companies":""}</small>
        </div>
        {data&&data.total?<nav className="rd-pagination" aria-label="Monthly churn pages">
          <button type="button" disabled={safePage===1} onClick={()=>setPage(v=>Math.max(1,v-1))} aria-label="Previous page"><Icon name="left"/></button>
          {paginationItems(safePage,pageCount).map((item,index)=>item==="ellipsis"?<span className="rd-page-ellipsis" key={"e-"+index}>…</span>:<button type="button" key={item} aria-current={safePage===item?"page":undefined} onClick={()=>setPage(item)}>{item}</button>)}
          <button type="button" disabled={safePage===pageCount} onClick={()=>setPage(v=>Math.min(pageCount,v+1))} aria-label="Next page"><Icon name="right"/></button>
        </nav>:null}
      </footer>
    </section>
  </div>;
}
