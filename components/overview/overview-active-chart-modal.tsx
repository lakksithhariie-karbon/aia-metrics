"use client";

import { useEffect, useRef, useState } from "react";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type {
  OverviewChartKind, OverviewChartSegment, OverviewChartUsersResponse,
  OverviewCoreModule, OverviewDrillUserRow, OverviewDrillCompanyRow,
} from "../../lib/overview/drill";
import { OverviewCompanyDetailModal, type OverviewCompanyFocus } from "./overview-usage-modals";

const nf = new Intl.NumberFormat("en-US");
const PAGE_SIZE = 10;

export interface ChartDrillTarget {
  kind: OverviewChartKind;
  key: string;
  label: string;
  windowLabel: string;
  firstSegment: OverviewChartSegment;
  expected: Record<OverviewChartSegment, number>;
  limitedTracking?: boolean;
}

function Icon({ name }: { name: "close" | "left" | "right" | "down" | "search" }) {
  return <svg className="rd-icon" aria-hidden="true"><use href={"#i-" + name} /></svg>;
}
function formatWhen(value: string | null | undefined): string {
  if (!value) return "Not recorded";
  return new Date(value).toLocaleString("en-GB", {
    timeZone: "Asia/Kolkata", day: "numeric", month: "short",
    hour: "2-digit", minute: "2-digit",
  }) + " IST";
}
function pagination(page: number, total: number): Array<number | "ellipsis"> {
  const pages = [...new Set([1, page-1, page, page+1, total])]
    .filter(value => value>0 && value<=total).sort((a,b)=>a-b);
  const out: Array<number | "ellipsis"> = [];
  pages.forEach((value,i)=>{
    if (i && value-pages[i-1]>1) out.push("ellipsis");
    out.push(value);
  });
  return out;
}
async function loadPage(
  snapshot: OverviewUsageSnapshot, target: ChartDrillTarget,
  segment: OverviewChartSegment, query: string, module: OverviewCoreModule,
  page: number, signal: AbortSignal,
): Promise<OverviewChartUsersResponse> {
  const response = await fetch("/api/overview-drill", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    cache: "no-store", signal,
    body: JSON.stringify({
      action: "chart_users", snapshot_id: snapshot.snapshotId,
      kind: target.kind, key: target.key, segment,
      query, module, page, page_size: PAGE_SIZE,
    }),
  });
  if (!response.ok) {
    throw new Error(response.status===409
      ? "A newer snapshot is available. Refresh this dashboard."
      : "Could not load this chart's users. Try again.");
  }
  const data = await response.json() as OverviewChartUsersResponse;
  if (data.contract!=="independent_core_active_chart_users_v1"
    || data.snapshot_id!==snapshot.snapshotId
    || data.kind!==target.kind || data.key!==target.key
    || data.segment!==segment || data.segment_total!==target.expected[segment]) {
    throw new Error("The chart and its users no longer reconcile. Refresh to reload the snapshot.");
  }
  return data;
}

export default function OverviewActiveChartModal({
  target, snapshot, onClose,
}: {
  target: ChartDrillTarget;
  snapshot: OverviewUsageSnapshot;
  onClose: () => void;
}) {
  const [segment,setSegment] = useState<OverviewChartSegment>(target.firstSegment);
  const [module,setModule] = useState<OverviewCoreModule>("all");
  const [query,setQuery] = useState("");
  const [deferredQuery,setDeferredQuery] = useState("");
  const [page,setPage] = useState(1);
  const [data,setData] = useState<OverviewChartUsersResponse|null>(null);
  const [loading,setLoading] = useState(true);
  const [error,setError] = useState<string|null>(null);
  const [retry,setRetry] = useState(0);
  const [expanded,setExpanded] = useState<Set<string>>(new Set());
  const [companyFocus,setCompanyFocus] = useState<OverviewCompanyFocus|null>(null);
  const focusReturn = useRef<HTMLButtonElement|null>(null);
  const resultsRef = useRef<HTMLDivElement>(null);
  const pageCache = useRef<Map<string,OverviewChartUsersResponse>>(new Map());

  useEffect(()=>{
    const timer=setTimeout(()=>setDeferredQuery(query),250);
    return ()=>clearTimeout(timer);
  },[query]);
  useEffect(()=>{
    setPage(1);
    setExpanded(new Set());
    resultsRef.current?.scrollTo({top:0});
  },[segment,module,deferredQuery]);
  const cacheKey = [
    snapshot.snapshotId,target.kind,target.key,segment,module,deferredQuery,page,
  ].join("|");
  useEffect(()=>{
    const controller=new AbortController();
    const cached=pageCache.current.get(cacheKey);
    if(cached){
      setData(cached);setLoading(false);setError(null);
      return ()=>controller.abort();
    }
    setData(null);setLoading(true);setError(null);
    loadPage(snapshot,target,segment,deferredQuery,module,page,controller.signal)
      .then(result=>{
        if(controller.signal.aborted)return;
        pageCache.current.set(cacheKey,result);
        setData(result);
      })
      .catch(e=>{
        if(!controller.signal.aborted)setError(e instanceof Error?e.message:"Unable to load users");
      })
      .finally(()=>{if(!controller.signal.aborted)setLoading(false)});
    return ()=>controller.abort();
  },[cacheKey,deferredQuery,module,page,retry,segment,snapshot,target]);

  useEffect(()=>{
    const previous=document.body.style.overflow;
    document.body.style.overflow="hidden";
    return ()=>{document.body.style.overflow=previous};
  },[]);
  useEffect(()=>{
    function keydown(event: KeyboardEvent) {
      if(event.key!=="Escape")return;
      if(companyFocus){
        event.preventDefault();
        setCompanyFocus(null);
        requestAnimationFrame(()=>focusReturn.current?.focus({preventScroll:true}));
      }else{
        event.preventDefault();
        onClose();
      }
    }
    window.addEventListener("keydown",keydown);
    return ()=>window.removeEventListener("keydown",keydown);
  },[companyFocus,onClose]);

  function toggle(id: string) {
    setExpanded(current=>current.has(id)?new Set():new Set([id]));
  }
  function viewCompany(
    user: OverviewDrillUserRow, company: OverviewDrillCompanyRow,
    trigger: HTMLButtonElement,
  ) {
    focusReturn.current=trigger;
    setCompanyFocus({
      userId:user.id,companyId:company.id,companyName:company.name,
      scope:target.kind,chartKey:target.key,chartSegment:segment,
    });
  }

  const tabs: Array<[OverviewChartSegment,string]> =
    target.kind==="weekly"
      ? [["all","All users"],["returning","Returning"],["first_observed","First observed"]]
      : [["all","Exactly "+target.key+" "+(target.key==="1"?"week":"weeks")]];
  const totalPages=Math.max(1,Math.ceil((data?.total??0)/PAGE_SIZE));
  const first=data?.rows.length?(page-1)*PAGE_SIZE+1:0;
  const last=data?.rows.length?first+data.rows.length-1:0;

  return (
    <>
      <div className="rd-overlay" role="presentation">
        <section className="rd-modal rd-activation-modal po-usage-modal po-chart-drill-modal"
          role="dialog" aria-modal="true" aria-labelledby="po-chart-users-title">
          <header className="rd-modal-head">
            <div>
              <p>Product Overview · {target.windowLabel}</p>
              <h2 id="po-chart-users-title">
                {target.kind==="weekly"?"Weekly core-active users":"Core usage frequency"}
              </h2>
              <span>{target.label} · {nf.format(target.expected[segment])} users</span>
            </div>
            <button type="button" className="rd-close" onClick={onClose} aria-label="Close chart drill">
              <Icon name="close" />
            </button>
          </header>
          <div className="po-usage-summary po-chart-summary">
            <div>
              <span>Selected population</span>
              <strong>{nf.format(target.expected[segment])}</strong>
            </div>
            <div>
              <span>Reporting window</span>
              <strong className="po-chart-summary-period">{target.windowLabel}</strong>
            </div>
            <div>
              <span>Basis</span>
              <strong className="po-chart-summary-period">Distinct core-work users</strong>
            </div>
          </div>
          {target.limitedTracking ? (
            <div className="po-chart-tracking-note">
              Activity tracking was incomplete in July 2026. Treat these counts as observed minima.
            </div>
          ) : null}
          <div className="rd-drill-toolbar po-usage-toolbar">
            <div className="rd-status-tabs" aria-label="Chart user segment">
              {tabs.map(([key,label])=>(
                <button type="button" key={key} aria-pressed={segment===key}
                  onClick={()=>setSegment(key)}>
                  {label}<span>{nf.format(target.expected[key])}</span>
                </button>
              ))}
            </div>
            <div className="po-usage-filters">
              <label className="po-usage-select-label">
                <span className="sr-only">Module</span>
                <select aria-label="Filter by module" value={module}
                  onChange={e=>setModule(e.currentTarget.value as OverviewCoreModule)}>
                  <option value="all">All modules</option>
                  <option value="ap">AP / Bills</option>
                  <option value="ar">AR / Invoices</option>
                  <option value="transactions">Transactions</option>
                </select>
              </label>
              <div className="rd-search">
                <Icon name="search"/>
                <input aria-label="Search users or companies"
                  placeholder="Search users or companies"
                  value={query} onChange={e=>setQuery(e.currentTarget.value)}/>
                {query?<button type="button" onClick={()=>setQuery("")} aria-label="Clear search">
                  <Icon name="close"/>
                </button>:null}
              </div>
            </div>
          </div>
          <div className="rd-table-wrap po-usage-table-wrap" ref={resultsRef}>
            {loading?<div className="rd-loading">Loading live users and companies…</div>
            :error?<div className="rd-empty po-usage-error">
              <span>{error}</span>
              <button type="button" onClick={()=>setRetry(n=>n+1)}>Try again</button>
            </div>
            :!data?<div className="rd-empty">No chart data available</div>
            :<table className="rd-activation-table po-usage-table">
              <thead><tr>
                <th scope="col"><span className="sr-only">Expand</span></th>
                <th scope="col">User / Company</th>
                <th scope="col">Companies</th>
                <th scope="col">Core actions</th>
                <th scope="col">Active days</th>
                <th scope="col">Last active</th>
                <th scope="col">AP</th><th scope="col">AR</th><th scope="col">Transaction</th>
              </tr></thead>
              <tbody>
                {data.rows.length?data.rows.flatMap(user=>{
                  const isOpen=expanded.has(user.id);
                  const parent=<tr key={"user:"+user.id} className={isOpen?"is-expanded":""}>
                    <td><button type="button" className="rd-expander"
                      aria-expanded={isOpen}
                      aria-label={(isOpen?"Collapse ":"Expand ")+user.email}
                      onClick={()=>toggle(user.id)}>
                      <Icon name={isOpen?"down":"right"}/>
                    </button></td>
                    <td><button className="rd-company-link po-usage-user-link"
                      type="button" onClick={()=>toggle(user.id)}>
                      <strong>{user.email}</strong>
                      <span>Distinct user · {nf.format(user.active_days)} active days</span>
                    </button></td>
                    <td><span className="po-usage-pill">{user.companies.length}</span></td>
                    <td className="has-value">{nf.format(user.actions)}</td>
                    <td>{nf.format(user.active_days)}</td>
                    <td>{formatWhen(user.last_active_at)}</td>
                    <td>{nf.format(user.modules.ap)}</td>
                    <td>{nf.format(user.modules.ar)}</td>
                    <td>{nf.format(user.modules.transactions)}</td>
                  </tr>;
                  if(!isOpen)return [parent];
                  return [parent,...user.companies.map(company=><tr
                    key={"company:"+user.id+":"+company.id}
                    className="po-usage-company-row rd-user-row">
                    <td/>
                    <td><span className="rd-user-indent">
                      <button type="button" className="po-usage-company-link"
                        onClick={e=>viewCompany(user,company,e.currentTarget)}>
                        {company.name}
                        <small>View full company breakdown →</small>
                      </button>
                    </span></td>
                    <td>{company.is_test?<span className="rd-status">Test</span>:"Company"}</td>
                    <td>{nf.format(company.actions)}</td>
                    <td>{nf.format(company.active_days)}</td>
                    <td>{formatWhen(company.last_active_at)}</td>
                    <td>{nf.format(company.modules.ap)}</td>
                    <td>{nf.format(company.modules.ar)}</td>
                    <td>{nf.format(company.modules.transactions)}</td>
                  </tr>)];
                }):<tr><td colSpan={9}><div className="rd-empty">
                  No matching users. Adjust the search or module filter.
                </div></td></tr>}
              </tbody>
            </table>}
          </div>
          <footer className="rd-modal-foot rd-modal-foot-paginated">
            <div className="rd-table-summary">
              <span>
                Independent core work only · Each user counted once
              </span>
              <small>{data?"Showing "+nf.format(first)+"–"+nf.format(last)+
                " of "+nf.format(data.total)+" users":
                "Pinned to snapshot #"+snapshot.snapshotId}</small>
            </div>
            {data&&totalPages>1?<nav className="rd-pagination" aria-label="Chart user pages">
              <button type="button" disabled={page<=1}
                aria-label="Previous page" onClick={()=>setPage(n=>n-1)}>
                <Icon name="left"/>
              </button>
              {pagination(page,totalPages).map((item,i)=>
                item==="ellipsis"?<span key={"ellipsis:"+i} className="rd-page-ellipsis">…</span>
                :<button type="button" key={item}
                  aria-current={page===item?"page":undefined}
                  onClick={()=>setPage(item)}>{item}</button>)}
              <button type="button" disabled={page>=totalPages}
                aria-label="Next page" onClick={()=>setPage(n=>n+1)}>
                <Icon name="right"/>
              </button>
            </nav>:null}
          </footer>
        </section>
      </div>
      {companyFocus?<OverviewCompanyDetailModal
        focus={companyFocus} snapshot={snapshot}
        onClose={()=>{
          setCompanyFocus(null);
          requestAnimationFrame(()=>focusReturn.current?.focus({preventScroll:true}));
        }}
      />:null}
    </>
  );
}
