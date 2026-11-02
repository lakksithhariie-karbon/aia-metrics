"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { BillExtractionRecord } from "../../lib/ai-services/types";
import type { LiveScope, LiveEvidence, LiveDashboard } from "../../lib/ai-services/live";
import { formatRecordedCost } from "../../lib/ai-services/format";

const number = new Intl.NumberFormat("en-IN");
const PAGE_SIZE = 10;

function shortId(uuid: string) { return uuid.slice(0, 8); }
function fmtDate(iso: string) {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? "—" : new Intl.DateTimeFormat("en-GB", {
    day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Kolkata",
  }).format(date);
}
function fmtCost(v: number | null, currency: "unverified" | "USD") { return formatRecordedCost(v, currency, 3); }
function fmtLatency(v: number | null) { return v === null ? "Unknown" : number.format(v) + " units"; }
function fmtStatus(value: string | null) {
  return value === "needs_review" ? "Needs review" : value === "reviewed" ? "Reviewed" : value === "deleted" ? "Deleted" : "Unknown";
}
function pageNumbers(page: number, count: number): Array<number | "…"> {
  if (count <= 6) return Array.from({ length: count }, (_, i) => i + 1);
  const keep = new Set([1, count, page - 1, page, page + 1].filter(x => x >= 1 && x <= count));
  const selected = [...keep].sort((a, b) => a - b);
  const result: Array<number | "…"> = [];
  selected.forEach((item, i) => {
    if (i && item - selected[i - 1] > 1) result.push("…");
    result.push(item);
  });
  return result;
}

/** The exact Product/Engineering overlay and header primitives, with a second
 * focus-contained portal for record details. Neither modal is a browser alert. */
function ModalShell({ title, eyebrow, description, onClose, children, wide = false, inactive = false, detail = false }: {
  title: string; eyebrow: string; description: string; onClose: () => void;
  children: React.ReactNode; wide?: boolean; inactive?: boolean; detail?: boolean;
}) {
  const titleId = useId();
  const closeRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);
  useEffect(() => {
    if (inactive) return;
    const before = document.body.style.overflow;
    previousFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus({ preventScroll: true });
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); onClose(); return; }
      if (event.key !== "Tab" || !panelRef.current) return;
      const focusable = Array.from(panelRef.current.querySelectorAll<HTMLElement>(
        'button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])',
      )).filter(el => el.tabIndex >= 0 && el.getClientRects().length > 0);
      if (!focusable.length) return;
      if (event.shiftKey && document.activeElement === focusable[0]) {
        event.preventDefault(); focusable[focusable.length - 1].focus();
      } else if (!event.shiftKey && document.activeElement === focusable[focusable.length - 1]) {
        event.preventDefault(); focusable[0].focus();
      }
    };
    document.addEventListener("keydown", onKey, true);
    return () => {
      document.removeEventListener("keydown", onKey, true);
      document.body.style.overflow = before;
      previousFocus.current?.focus({ preventScroll: true });
    };
  }, [inactive, onClose]);
  return createPortal(
    <div className={"ed-overlay ai-modal-overlay" + (detail ? " ai-modal-level-two" : "")}
      role="presentation"
      onMouseDown={event => { if (event.target === event.currentTarget && !inactive) onClose(); }}>
      <section ref={panelRef} role="dialog" aria-modal={!inactive} aria-hidden={inactive || undefined}
        aria-labelledby={titleId}
        className={"rd-modal rd-activation-modal ed-investigation-modal ai-investigation-modal" + (wide ? " ai-drill-wide" : "") + (detail ? " ai-detail-modal" : "")}>
        <header className="rd-modal-head ed-investigation-head ai-investigation-head">
          <div>
            <p>{eyebrow}</p>
            <h2 id={titleId}>{title}</h2>
            <span>{description}</span>
          </div>
          <button ref={closeRef} type="button" className="rd-close ed-investigation-close"
            onClick={onClose} aria-label={"Close " + title}>
            <svg viewBox="0 0 24 24" width="17" height="17" aria-hidden="true"><path d="m5 5 14 14M19 5 5 19" stroke="currentColor" fill="none" strokeWidth="1.8" strokeLinecap="round" /></svg>
          </button>
        </header>
        {children}
      </section>
    </div>, document.body,
  );
}

function DrillSummary({ rows }: { rows: Array<{ label: string; value: string; note?: string }> }) {
  return <div className="ai-drill-summary" aria-label="Investigation summary">
    {rows.map(row => <div key={row.label}>
      <span>{row.label}</span><strong>{row.value}</strong>{row.note ? <small>{row.note}</small> : null}
    </div>)}
  </div>;
}

function DrillSearch({ query, onChange, placeholder, disabled = false }: { query: string; onChange: (v: string) => void; placeholder: string; disabled?: boolean }) {
  return <div className="rd-search ed-investigation-search ai-investigation-search">
    <svg className="rd-icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.7">
      <circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/>
    </svg>
    <input type="search" placeholder={placeholder} aria-label={placeholder}
      value={query} disabled={disabled} onChange={event => onChange(event.currentTarget.value)} />
    {query ? <button type="button" onClick={() => onChange("")} aria-label="Clear search">×</button> : null}
  </div>;
}

function DrillPagination({ page, pages, shown, total, label, onPage }: {
  page: number; pages: number; shown: number; total: number; label: string;
  onPage: (page: number) => void;
}) {
  const first = shown ? (page - 1) * PAGE_SIZE + 1 : 0;
  const last = shown ? first + shown - 1 : 0;
  return <footer className="rd-modal-foot rd-modal-foot-paginated ai-investigation-foot">
    <div className="rd-table-summary"><span>{label}</span>
      <small>Showing {number.format(first)}–{number.format(last)} of {number.format(total)}</small>
    </div>
    {pages > 1 ? <nav className="rd-pagination" aria-label="Investigation pages">
      <button type="button" disabled={page === 1} onClick={() => onPage(page - 1)} aria-label="Previous page">‹</button>
      {pageNumbers(page, pages).map((item, i) => item === "…"
        ? <span key={"ellipsis" + i} className="rd-page-ellipsis">…</span>
        : <button type="button" key={item} aria-current={page === item ? "page" : undefined}
            onClick={() => onPage(item)}>{item}</button>)}
      <button type="button" disabled={page === pages} onClick={() => onPage(page + 1)} aria-label="Next page">›</button>
    </nav> : null}
  </footer>;
}

type SortKey = "createdAt" | "knownTotalCost" | "knownTotalLatency";

async function fetchEvidence(scope: LiveScope, drill: string, value: string, query: string,
  sort: SortKey, direction: "asc"|"desc", page: number, signal: AbortSignal): Promise<LiveEvidence> {
  const response = await fetch("/api/ai-services/report", {
    method:"POST",cache:"no-store",signal,headers:{"Content-Type":"application/json"},
    body:JSON.stringify({scope:{...scope,search:scope.search || query.trim()},drill,value,
      sort,direction,offset:(page-1)*PAGE_SIZE}),
  });
  if (!response.ok) throw Error("bill_evidence_unavailable");
  const data=await response.json() as LiveEvidence;
  if(data?.contract!=="ai_bill_extraction_records_v1"||!Array.isArray(data.rows)||data.rows.length>PAGE_SIZE)
    throw Error("bill_evidence_contract_invalid");
  return data;
}

export function BillRecordsModal({ title, subtitle, coverage, scope, currency, drillKind, drillValue, onClose }: {
  title:string;subtitle:string;coverage:string;scope:LiveScope;currency:"unverified"|"USD";
  drillKind:string;drillValue:string;onClose:()=>void;
}) {
  const [query,setQuery]=useState("");
  const [search,setSearch]=useState("");
  const [sortKey,setSortKey]=useState<SortKey>(drillKind==="known_latency"||drillKind==="month_latency"?"knownTotalLatency":"createdAt");
  const [sortDir,setSortDir]=useState<"asc"|"desc">("desc");
  const [page,setPage]=useState(1);
  const [detail,setDetail]=useState<BillExtractionRecord|null>(null);
  const [data,setData]=useState<LiveEvidence|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState(false);
  const [retry,setRetry]=useState(0);
  const tableRef=useRef<HTMLDivElement>(null);
  const recordTrigger=useRef<HTMLButtonElement|null>(null);
  useEffect(()=>{const timeout=setTimeout(()=>setSearch(query),260);return ()=>clearTimeout(timeout);},[query]);
  useEffect(()=>{
    const ac=new AbortController();setLoading(true);setError(false);setData(null);
    fetchEvidence(scope,drillKind,drillValue,search,sortKey,sortDir,page,ac.signal)
      .then(value=>{if(!ac.signal.aborted){setData(value);setLoading(false);}})
      .catch(()=>{if(!ac.signal.aborted){setError(true);setLoading(false);}});
    return ()=>ac.abort();
  },[scope,drillKind,drillValue,search,sortKey,sortDir,page,retry]);
  const filtered=data?.rows??[];
  const pages=Math.max(1,Math.ceil((data?.total??0)/PAGE_SIZE));
  const toggleSort=(key:SortKey)=>{if(sortKey===key)setSortDir(d=>d==="asc"?"desc":"asc");
    else{setSortKey(key);setSortDir("desc");}setPage(1);tableRef.current?.scrollTo({top:0});};
  const openDetail=(r:BillExtractionRecord,button:HTMLButtonElement)=>{recordTrigger.current=button;setDetail(r);};
  const closeDetail=()=>{setDetail(null);requestAnimationFrame(()=>recordTrigger.current?.focus({preventScroll:true}));};
  const headerSort=(key:SortKey,label:string)=><button type="button" className="ed-investigation-sort"
    onClick={()=>toggleSort(key)}>{label}<span aria-hidden="true">{sortKey===key?(sortDir==="asc"?"↑":"↓"):"↕"}</span></button>;
  return <>
    <ModalShell title={title} eyebrow="AI Services · Bill extraction" description={subtitle} onClose={onClose} wide inactive={!!detail}>
      <DrillSummary rows={[
        {label:"Matching extractions",value:loading?"…":number.format(data?.total??0),note:"Selected chart / KPI population"},
        {label:"Dashboard coverage",value:coverage,note:"Unknown values remain excluded"},
        {label:"Known cost",value:loading?"…":number.format(data?.knownCostCount??0)+" / "+number.format(data?.total??0),note:currency==="USD"?"USD display, source unit unverified":"Cost currency unverified"},
      ]}/>
      <div className="rd-drill-toolbar ed-investigation-toolbar ai-investigation-toolbar">
        <DrillSearch query={query} onChange={v=>{setQuery(v);setPage(1);}} disabled={!!scope.search} placeholder={scope.search?"Dashboard search is active":"Search prediction or company"} />
        <span className="ai-investigation-toolbar-note">{scope.search?"Results scoped by dashboard search":loading?"Loading records…":number.format(data?.total??0)+" matching records"}</span>
      </div>
      <div className="rd-table-wrap ed-investigation-table-wrap ai-records-table-wrap" ref={tableRef}>
        {error?<div role="alert" className="ed-investigation-error"><p>Verified extraction records are unavailable. No sample data is shown.</p><button type="button" onClick={()=>setRetry(x=>x+1)}>Try again</button></div>:
        <table className="rd-activation-table ed-investigation-table ai-records-table">
          <thead><tr>
            <th scope="col">Prediction</th>
            <th scope="col" aria-sort={sortKey==="createdAt"?(sortDir==="asc"?"ascending":"descending"):"none"}>{headerSort("createdAt","Created")}</th>
            <th scope="col">Company</th><th scope="col">Document</th><th scope="col">Pages</th>
            <th scope="col" aria-sort={sortKey==="knownTotalCost"?(sortDir==="asc"?"ascending":"descending"):"none"}>{headerSort("knownTotalCost","Cost")}</th>
            <th scope="col" aria-sort={sortKey==="knownTotalLatency"?(sortDir==="asc"?"ascending":"descending"):"none"}>{headerSort("knownTotalLatency","Latency")}</th>
            <th scope="col">Review status</th>
          </tr></thead>
          <tbody>{loading?<tr className="ed-investigation-row"><td colSpan={8}>Loading verified evidence…</td></tr>:
            filtered.length?filtered.map(r=><tr key={r.predictionUuid} className="ed-investigation-row">
              <td><button type="button" className="ed-investigation-key ai-prediction-link"
                onClick={event=>openDetail(r,event.currentTarget)} title={r.predictionUuid}
                aria-label={"Open extraction "+r.predictionUuid}>{shortId(r.predictionUuid)} <span aria-hidden="true">↗</span></button></td>
              <td>{fmtDate(r.createdAt)}</td><td title={r.companyName}>{r.companyName}</td>
              <td className="ai-capitalize">{r.docType??"Unknown"}</td><td>{r.totalPages??"—"}</td>
              <td className={r.knownTotalCost===null?"ai-unknown":""}>{fmtCost(r.knownTotalCost,currency)}</td>
              <td className={r.knownTotalLatency===null?"ai-unknown":""}>{fmtLatency(r.knownTotalLatency)}</td>
              <td><span className={"ai-review-pill ai-review-"+(r.reviewStatus??"unknown")}>{fmtStatus(r.reviewStatus)}</span></td>
            </tr>):<tr className="ed-investigation-row"><td colSpan={8} className="ai-records-empty">No extractions match this selection.</td></tr>}</tbody>
        </table>}
      </div>
      <DrillPagination page={page} pages={pages} shown={filtered.length} total={data?.total??0}
        label="Prediction-level evidence · Live Supabase" onPage={next=>{setPage(next);tableRef.current?.scrollTo({top:0});}} />
    </ModalShell>
    {detail?<BillDetailModal record={detail} currency={currency} onClose={closeDetail}/>:null}
  </>;
}

export function BillCompaniesModal({ companies, scope, currency, bills, coverage, period, onClose }: {
  companies:LiveDashboard["companies"];scope:LiveScope;currency:"unverified"|"USD";bills:number;coverage:string;period:string;onClose:()=>void;
}) {
  const [query,setQuery]=useState("");
  const [page,setPage]=useState(1);
  const [selected,setSelected]=useState<{id:string;name:string}|null>(null);
  const shown=companies.filter(c=>c.companyName.toLowerCase().includes(query.toLowerCase().trim()));
  const pages=Math.max(1,Math.ceil(shown.length/PAGE_SIZE));
  const safePage=Math.min(page,pages);
  return <>
    <ModalShell title="Active companies" eyebrow="AI Services · Company consumption"
      description={period+" · distinct companies with at least one extraction"}
      onClose={onClose} wide inactive={!!selected}>
      <DrillSummary rows={[
        {label:"Active companies",value:number.format(companies.length),note:"One row per company"},
        {label:"Bill extractions",value:number.format(bills),note:"Selected reporting period"},
        {label:"Dashboard coverage",value:coverage,note:"Selected customer classification"},
      ]}/>
      <div className="rd-drill-toolbar ed-investigation-toolbar ai-investigation-toolbar">
        <DrillSearch query={query} onChange={v=>{setQuery(v);setPage(1);}} placeholder="Search companies"/>
        <span className="ai-investigation-toolbar-note">Select a company to inspect its predictions</span>
      </div>
      <div className="rd-table-wrap ed-investigation-table-wrap ai-records-table-wrap">
        <table className="rd-activation-table ed-investigation-table ai-companies-table">
          <thead><tr><th scope="col">Company</th><th scope="col">Bills</th><th scope="col">Known cost</th><th scope="col">Cost coverage</th><th scope="col">Needs review</th></tr></thead>
          <tbody>{shown.slice((safePage-1)*PAGE_SIZE,safePage*PAGE_SIZE).map(c=><tr className="ed-investigation-row" key={c.companyUuid}>
            <td><button type="button" className="ed-investigation-key" onClick={()=>setSelected({id:c.companyUuid,name:c.companyName})}>{c.companyName} <span aria-hidden="true">↗</span></button></td>
            <td>{number.format(c.bills)}</td><td>{formatRecordedCost(c.knownCost,currency,1)}</td>
            <td>{number.format(c.bills-c.unknownCostCount)} / {number.format(c.bills)}</td>
            <td>{number.format(c.needsReview)}</td>
          </tr>)}{shown.length===0?<tr className="ed-investigation-row"><td colSpan={5} className="ai-records-empty">No companies match this search.</td></tr>:null}</tbody>
        </table>
      </div>
      <DrillPagination page={safePage} pages={pages} shown={shown.slice((safePage-1)*PAGE_SIZE,safePage*PAGE_SIZE).length}
        total={shown.length} label="Company-level summary · Live Supabase" onPage={setPage}/>
    </ModalShell>
    {selected?<BillRecordsModal title={"Extraction history · "+selected.name} subtitle={period} coverage={coverage}
      scope={scope} currency={currency} drillKind="company" drillValue={selected.id} onClose={()=>setSelected(null)}/>:null}
  </>;
}

export function BillDetailModal({ record, currency, onClose }: {
  record: BillExtractionRecord; currency:"unverified"|"USD"; onClose: () => void;
}) {
  const rows: Array<[string, string]> = [
    ["Prediction ID", record.predictionUuid], ["File ID", record.fileUuid ?? "Not recorded"],
    ["Company", record.companyName], ["Customer classification", record.companyScope.replaceAll("_", " ")],
    ["Created", fmtDate(record.createdAt)], ["Loaded", fmtDate(record.loadedAt)],
    ["Review status", fmtStatus(record.reviewStatus)],
    ["Document type", record.docType ?? "Unknown"], ["Pages", record.totalPages === null ? "Unknown" : String(record.totalPages)],
    ["Legibility score", record.legibilityScore === null ? "Unknown" : record.legibilityScore.toFixed(2)],
    ["Extraction cost", fmtCost(record.extractionCost,currency)], ["Enrichment cost", fmtCost(record.enrichmentCost,currency)],
    ["Known total cost", fmtCost(record.knownTotalCost,currency) + (record.completeCostBreakdown ? "" : " · incomplete breakdown")],
    ["Extraction latency", fmtLatency(record.extractionLatency)], ["Enrichment latency", fmtLatency(record.enrichmentLatency)],
    ["Known total latency", fmtLatency(record.knownTotalLatency) + (record.completeLatencyBreakdown ? "" : " · incomplete breakdown")],
    ["Raw artifact", record.hasRaw ? "Available" : "Not stored"],
  ];
  return <ModalShell title={"Extraction " + shortId(record.predictionUuid)}
    eyebrow="AI Services · Prediction detail" description="Recorded fields · point-in-time evidence"
    onClose={onClose} detail>
    <button type="button" className="ai-detail-back" onClick={onClose}>← Back to results</button>
    <div className="ai-record-detail-scroll"><dl className="ai-record-detail">
      {rows.map(([term, value]) => <div key={term}><dt>{term}</dt><dd>{value}</dd></div>)}
    </dl></div>
    <p className="ai-detail-footnote">Review status is a snapshot, not an extraction accuracy score. Costs are displayed in USD at product direction; source currency is not independently verified. Latency units remain unverified.</p>
  </ModalShell>;
}
