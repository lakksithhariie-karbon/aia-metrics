"use client";

import { useEffect, useMemo, useState } from "react";
import ProductMonthRangePicker from "../ui/product-month-range-picker";
import CompactMenuSelect from "../ui/compact-menu-select";
import type { CompactSelectOption } from "../ui/compact-menu-select";
import MetricsInfoDialog, { MetricsInfoButton } from "../ui/metrics-info";
import type { MetricsInfoDefinition } from "../ui/metrics-info";
import MetricsInvestigationTable from "../ui/metrics-investigation-table";
import type { MetricsInvestigationRow } from "../ui/metrics-investigation-table";
import { completedPreset } from "../../lib/infra/date-range";
import type { MonthRange } from "../../lib/infra/date-range";
import type { ScopeFilter } from "../../lib/ai-services/types";
import { SCOPE_FILTER_LABELS } from "../../lib/ai-services/types";
import { scopesForFilter } from "../../lib/ai-services/types";
import type { LiveDashboard, LiveScope } from "../../lib/ai-services/live";

import { BillCompaniesModal, BillRecordsModal } from "./bill-drills";

const AS_OF = new Date().toISOString();
const CURRENT_MONTH = AS_OF.slice(0, 7);
const EMPTY_KPIS = { bills:0,companies:0,knownCostTotal:0,knownCostCount:0,unknownCostCount:0,avgKnownCost:null,p50Latency:null,p95Latency:null,knownLatencyCount:0,unknownLatencyCount:0,needsReviewCount:0,needsReviewRate:null };

const INFO: Record<string, MetricsInfoDefinition> = {
  bills: {
    title: "Bills processed",
    logic: "Count of bill extraction predictions in the selected months and customer scope. Volume counts every prediction, including rows with unknown cost.",
    example: "120 predictions in September = 120 bills processed.",
    note: "Verified source data. Unknown costs do not reduce the bill count.",
  },
  companies: {
    title: "Active companies",
    logic: "Distinct companies with at least one bill extraction in the selected months and scope.",
    example: "9 companies with extractions in September = 9 active companies.",
    note: "Verified source data.",
  },
  cost: {
    title: "Recorded AI cost",
    logic: "Sum of known total cost: the source total unless both cost components are missing, in which case the row contributes nothing. Zero is never substituted for missing costs.",
    example: "100 known rows summing to 250.5 cost units, 14 unknown rows excluded.",
    note: "Verified source data. Cost currency is not confirmed — values are labeled cost units. This is not total spend.",
  },
  avg: {
    title: "Average known cost per bill",
    logic: "Sum of known total cost divided by the count of known-cost extractions in scope. Unknown-cost rows are excluded from numerator and denominator.",
    example: "250.5 / 100 known = 2.505 cost units per bill.",
    note: "Verified source data. Disclose the excluded unknown count alongside this average.",
  },
  latency: {
    title: "Processing latency P95",
    logic: "Nearest-rank 95th percentile of known total latency in scope. Unknown latencies are excluded, never treated as zero.",
    example: "P95 of 120 latency units means 5% of known extractions took longer.",
    note: "Verified source data. Latency units are not confirmed.",
  },
  review: {
    title: "Needs-review rate",
    logic: "Extractions with review status needs_review divided by all extractions in scope. Review status is a point-in-time snapshot, not extraction accuracy.",
    example: "15 needs-review / 100 extractions = 15%.",
    note: "Verified source data. Do not read this as a failure or error rate.",
  },
};

const SCOPE_OPTIONS: ReadonlyArray<CompactSelectOption<ScopeFilter>> = (
  Object.keys(SCOPE_FILTER_LABELS) as ScopeFilter[]
).map(value => ({ value, label: SCOPE_FILTER_LABELS[value] }));

const DOC_OPTIONS = [
  { value: "all", label: "All document types" },
  { value: "scanned", label: "Scanned" },
  { value: "digital", label: "Digital" },
  { value: "handwritten", label: "Handwritten" },
  { value: "unknown", label: "Unknown type" },
] as const;

const STATUS_OPTIONS = [
  { value: "all", label: "All review statuses" },
  { value: "reviewed", label: "Reviewed" },
  { value: "needs_review", label: "Needs review" },
  { value: "deleted", label: "Deleted" },
  { value: "unknown", label: "Unknown status" },
] as const;

type Drill = { title: string; subtitle: string; kind: string; value: string } | null;

function MetricCard({ label, period, value, note, onDrill, onInfo }: {
  label: string; period: string; value: string; note: string;
  onDrill: () => void; onInfo: () => void;
}) {
  return (
    <div className="ed-metric-wrap">
      <button
        type="button"
        className="metric-card ed-metric"
        onClick={onDrill}
        aria-haspopup="dialog"
        aria-label={label + ": " + value + ". Open supporting breakdown."}
      >
        <span className="po-kpi-divider" aria-hidden="true" />
        <span className="metric-label">{label}</span>
        <span className="metric-period">{period}</span>
        <span className="metric-value">{value}</span>
        <span className="metric-note">{note}</span>
      </button>
      <MetricsInfoButton className="ed-info-button" label={"How " + label + " is calculated"} onClick={onInfo} />
    </div>
  );
}

function Surface({ title, subtitle, infoKey, onInfo, half = false, children }: {
  title: string; subtitle: string; infoKey: string; onInfo: (key: string) => void; half?: boolean; children: React.ReactNode;
}) {
  return (
    <article className={"report-card ed-report" + (half ? " ed-report-half" : "")}>
      <header className="report-header ed-report-heading">
        <div>
          <h2>{title}</h2>
          <p className="report-subtitle">{subtitle}</p>
        </div>
        <MetricsInfoButton label={"How " + title + " is counted"} onClick={() => onInfo(infoKey)} />
      </header>
      {children}
    </article>
  );
}

function SectionHead({ title, question }: { title: string; question: string }) {
  return <div className="metrics-section-kicker ed-section-heading"><span>{title}</span><span className="metrics-section-description">{question}</span></div>;
}

const number = new Intl.NumberFormat("en-IN", { maximumFractionDigits: 0 });
const compact = (value: number) => value >= 1000 ? new Intl.NumberFormat("en-IN", { notation: "compact", maximumFractionDigits: 1 }).format(value) :
  value >= 100 ? number.format(Math.round(value)) : value.toFixed(value < 10 ? 1 : 0);
const monthName = (month: string) => new Date(month + "-01T12:00:00Z")
  .toLocaleDateString("en-GB", { month: "short", timeZone: "UTC" });

function MonthBars({ points, total, onSelect, emptyLabel }: {
  points: Array<{ month: string; value: number; note?: string }>;
  total: number;
  onSelect: (month: string) => void;
  emptyLabel: string;
}) {
  const max = Math.max(1, ...points.map(p => p.value));
  if (!points.length || total === 0) return <p className="ed-chart-empty">{emptyLabel}</p>;
  return <div className="ai-chart" role="group" aria-label="Monthly values bar chart">
    <div className="ai-chart-scale" aria-hidden="true"><span>{compact(max)}</span><span>{compact(max / 2)}</span><span>0</span></div>
    <div className="ai-chart-plot">
      <div className="ai-chart-guides" aria-hidden="true"><span /><span /><span /></div>
      <div className="ai-bars">
        {points.map(p => <button type="button" key={p.month} className="ai-bar"
          onClick={() => onSelect(p.month)} title={p.month + ": " + compact(p.value) + (p.note ? " · " + p.note : "")}
          aria-label={p.month + ": " + p.value + (p.note ? ". " + p.note : "") + ". Open matching extractions."}>
          <span className="ai-bar-value">{compact(p.value)}</span>
          <span className="ai-bar-rail"><span className="ai-bar-fill" style={{ height: (p.value / max * 100).toFixed(2) + "%" }}/></span>
          <span className="ai-bar-month">{monthName(p.month)}</span>
        </button>)}
      </div>
    </div>
  </div>;
}

function ComponentBreakdown({ stats, bills, onOpen }: { stats: LiveDashboard["components"]; bills: number; onOpen: (key: "extraction" | "enrichment") => void }) {
  const values = [
    { key: "extraction" as const, label: "Extraction", value: stats.extraction },
    { key: "enrichment" as const, label: "Enrichment", value: stats.enrichment },
  ];
  const total = values.reduce((s, r) => s + r.value, 0);
  return <div className="ai-detail-chart">
    <div className="ai-chart-headline"><strong>{total.toFixed(1)}</strong><span>cost units across {number.format(stats.count)} fully itemized bills</span></div>
    <div className="ai-split-bar" role="img" aria-label="Cost component proportions">
      {values.map((r, i) => <span key={r.key} className={"ai-split-section ai-split-" + i} style={{ width: (total ? r.value / total * 100 : 0) + "%" }} />)}
    </div>
    <div className="ai-distribution-list">
      {values.map((r, i) => <button className="ai-distribution-row" type="button" key={r.key} onClick={() => onOpen(r.key)}>
        <span className="ai-distribution-name"><i className={"ai-swatch ai-swatch-" + i} />{r.label}</span>
        <strong>{r.value.toFixed(1)} <small>units</small></strong>
        <span className="ai-distribution-percent">{total ? (r.value / total * 100).toFixed(1) : "0.0"}%</span>
      </button>)}
    </div>
    <p className="ai-chart-footnote">{number.format(bills - stats.count)} bills excluded from component comparison. Select a component to inspect the contributing bills.</p>
  </div>;
}

function LatencyComparison({ points, onSelect }: { points: Array<{ month: string; p50Latency: number | null; p95Latency: number | null }>; onSelect: (month: string) => void }) {
  const ready = points.filter(p => p.p50Latency !== null && p.p95Latency !== null);
  const max = Math.max(1, ...ready.map(p => p.p95Latency ?? 0));
  if (!ready.length) return <p className="ed-chart-empty">No known latencies in this period.</p>;
  return <div className="ai-detail-chart ai-latency-chart">
    <div className="ai-legend"><span><i className="ai-swatch ai-swatch-0" />P50</span><span><i className="ai-swatch ai-swatch-1" />P95</span><small>Latency units unverified</small></div>
    <div className="ai-latency-list">
      {ready.map(p => <button key={p.month} className="ai-latency-row" type="button" onClick={() => onSelect(p.month)} title={p.month + " · P50 " + p.p50Latency + " · P95 " + p.p95Latency}>
        <span className="ai-latency-month">{monthName(p.month)}</span>
        <span className="ai-latency-tracks"><i className="ai-latency-p50" style={{width: ((p.p50Latency ?? 0) / max * 100) + "%"}} /><i className="ai-latency-p95" style={{width: ((p.p95Latency ?? 0) / max * 100) + "%"}} /></span>
        <span className="ai-latency-values">{p.p50Latency} / <strong>{p.p95Latency}</strong></span>
      </button>)}
    </div>
    <p className="ai-chart-footnote">P50 / P95 per month. Select a month for its known-latency extractions.</p>
  </div>;
}

function DistributionRows({ rows, total, onSelect }: { rows: Array<{ key: string; label: string; count: number }>; total: number; onSelect: (key: string) => void }) {
  return <div className="ai-detail-chart ai-dist-chart">
    <div className="ai-chart-headline"><strong>{number.format(total)}</strong><span>predictions in selected scope</span></div>
    <div className="ai-distribution-list">
      {rows.map((r, i) => <button key={r.key} className="ai-distribution-row" type="button" onClick={() => onSelect(r.key)}>
        <span className="ai-distribution-name"><i className={"ai-swatch ai-swatch-" + i} />{r.label}</span>
        <span className="ai-distribution-track" aria-hidden="true"><i className={"ai-fill-" + i} style={{width: (total ? r.count / total * 100 : 0) + "%"}}/></span>
        <strong>{number.format(r.count)}</strong>
        <span className="ai-distribution-percent">{total ? (r.count / total * 100).toFixed(1) : "0.0"}%</span>
      </button>)}
    </div>
    {!rows.length ? <p className="ed-chart-empty">No extractions in scope.</p> : null}
    <p className="ai-chart-footnote">Select a category to view its underlying extractions.</p>
  </div>;
}

function LegibilityRows({ buckets, onSelect }: { buckets: Array<{ bucket: string; bills: number; needsReview: number }>; onSelect: (bucket: string) => void }) {
  return <div className="ai-detail-chart ai-dist-chart">
    <div className="ai-legend"><span><i className="ai-swatch ai-swatch-warn" />Needs review</span><small>Rate within each score bucket</small></div>
    <div className="ai-distribution-list">
      {buckets.filter(b => b.bills > 0).map(b => {
        const rate = b.needsReview / b.bills * 100;
        return <button type="button" key={b.bucket} className="ai-distribution-row" onClick={() => onSelect(b.bucket)}>
          <span className="ai-distribution-name">{b.bucket}</span>
          <span className="ai-distribution-track" aria-hidden="true"><i className="ai-fill-warn" style={{width: rate + "%"}} /></span>
          <strong>{rate.toFixed(1)}%</strong><span className="ai-distribution-percent">{b.needsReview}/{b.bills}</span>
        </button>;
      })}
    </div>
    <p className="ai-chart-footnote">Legibility is an input signal, not an extraction accuracy score.</p>
  </div>;
}

export default function AiServicesOverview() {
  const [range, setRange] = useState<MonthRange>(() => completedPreset("6", AS_OF));
  const [scope, setScope] = useState<ScopeFilter>("verified");
  const [doc, setDoc] = useState<string>("all");
  const [status, setStatus] = useState<string>("all");
  const [search, setSearch] = useState("");
  const [drill, setDrill] = useState<Drill>(null);
  const [companyDrill, setCompanyDrill] = useState(false);
  const [infoKey, setInfoKey] = useState<string | null>(null);

  const from = range.start ?? "2026-08";
  const to = range.end ?? CURRENT_MONTH;
  const labelMonth = (month: string) => new Date(month + "-01T12:00:00Z")
    .toLocaleDateString("en-GB", { month: "short", year: "numeric", timeZone: "UTC" });
  const periodLabel = range.start && range.end
    ? range.start === range.end ? labelMonth(range.start) : labelMonth(range.start) + " – " + labelMonth(range.end)
    : "Lifetime";
  const [data, setData] = useState<LiveDashboard | null>(null);
  const [loading, setLoading] = useState(true);
  
  const [error, setError] = useState(false);
  const [debouncedSearch,setDebouncedSearch]=useState("");
  useEffect(() => { const t=setTimeout(()=>setDebouncedSearch(search),260);return ()=>clearTimeout(t); },[search]);
  const liveScope: LiveScope = useMemo(() => ({
    from,to,scopes:scopesForFilter(scope),doc,status,search:debouncedSearch,
  }),[from,to,scope,doc,status,debouncedSearch]);
  useEffect(() => {
    const abort = new AbortController();
    const q = new URLSearchParams({from:liveScope.from,to:liveScope.to,doc:liveScope.doc,status:liveScope.status,search:liveScope.search});
    liveScope.scopes.forEach(s=>q.append("scope",s));
    setLoading(true); setError(false);
    fetch("/api/ai-services/report?"+q.toString(),{cache:"no-store",signal:abort.signal})
      .then(async r=>{ if(!r.ok)throw Error("unavailable");return r.json() as Promise<LiveDashboard>; })
      .then(d=>{if(!abort.signal.aborted){setData(d);setLoading(false);}})
      .catch(()=>{if(!abort.signal.aborted){setData(null);setError(true);setLoading(false);}});
    return ()=>abort.abort();
  },[liveScope]);
  const kpis=data?.kpis??EMPTY_KPIS;
  const months=data?.months??[];
  const docs=data?.docs??[];
  const reviews=data?.reviews??[];
  const buckets=data?.buckets??[];
  const companyRows=data?.companies??[];
  const exceptions=data?.exceptions??{missingCost:0,missingLatency:0,missingPages:0,missingDocType:0,missingLegibility:0,partialBreakdown:0,testScope:0,unverifiedScope:0};

  const coverage = kpis.knownCostCount + " known of " + kpis.bills + " bills";
  const scopeNote = scope === "verified" ? "Verified customers" : "Includes " + SCOPE_FILTER_LABELS[scope].toLowerCase() + " — non-production scope";

  const openDrill = (title: string, subtitle: string, kind = "all", value = "") => {
    if (!loading) setDrill({ title, subtitle, kind, value });
  };

  const reset = () => {
    setRange(completedPreset("6", AS_OF));
    setScope("verified");
    setDoc("all");
    setStatus("all");
    setSearch("");
    setDrill(null);
  };

  const exceptionRows: MetricsInvestigationRow[] = [
    { id: "missing-cost", label: "Missing cost", value: String(exceptions.missingCost), detail: "reported as unknown, never zero",
      onOpen: exceptions.missingCost ? () => openDrill("Missing cost", periodLabel, "missing_cost") : undefined },
    { id: "missing-latency", label: "Missing latency", value: String(exceptions.missingLatency), detail: "reported as unknown, never zero",
      onOpen: exceptions.missingLatency ? () => openDrill("Missing latency", periodLabel, "missing_latency") : undefined },
    { id: "missing-pages", label: "Missing page counts", value: String(exceptions.missingPages), detail: "page metrics excluded",
      onOpen: exceptions.missingPages ? () => openDrill("Missing page counts", periodLabel, "missing_pages") : undefined },
    { id: "missing-doctype", label: "Missing document type", value: String(exceptions.missingDocType), detail: "kept as unknown type",
      onOpen: exceptions.missingDocType ? () => openDrill("Missing document type", periodLabel, "missing_doc") : undefined },
    { id: "missing-legibility", label: "Missing legibility", value: String(exceptions.missingLegibility), detail: "not a correctness score",
      onOpen: exceptions.missingLegibility ? () => openDrill("Missing legibility", periodLabel, "missing_legibility") : undefined },
    { id: "partial-breakdown", label: "Partial cost breakdowns", value: String(exceptions.partialBreakdown), detail: "only compare where complete",
      onOpen: exceptions.partialBreakdown ? () => openDrill("Partial cost breakdowns", periodLabel, "partial_breakdown") : undefined },
  ];

  if (!data) return <div className="ed-shell ai-shell"><main className="rd-page ed-page" role={error?"alert":"status"}>
    <div className="rd-page-head"><div className="ed-page-copy"><h1>Bill Extraction Overview</h1>
    <p>{error?"Verified reporting data is unavailable. No sample or stale values are shown.":loading?"Loading verified bill extraction reporting…":"No reporting data."}</p></div></div>
    {error?<button className="ui-control" type="button" onClick={()=>location.reload()}>Retry</button>:null}
    </main></div>;
  return (
    <div className="ed-shell ai-shell">
      <main className="rd-page ed-page">
        <div className="rd-page-head ed-page-head ai-page-head">
          <div className="ed-page-copy">
            <h1>Bill Extraction Overview</h1>
            <p>AI Services / Bill Extraction <span aria-hidden="true">·</span> Live reporting · verified source records</p>
          </div>
          <div className="ed-filters ai-filter-toolbar" role="group" aria-label="Bill extraction filters">
            <ProductMonthRangePicker value={range} asOf={CURRENT_MONTH} firstMonth={(data?.firstMonth ?? "2026-08")} onApply={next => { setRange(next); setDrill(null); }} />
            <CompactMenuSelect value={scope} options={SCOPE_OPTIONS} onChange={v => { setScope(v); setDrill(null); }} ariaLabel="Customer scope" />
            <CompactMenuSelect value={doc} options={DOC_OPTIONS} onChange={v => { setDoc(v); setDrill(null); }} ariaLabel="Document type" />
            <CompactMenuSelect value={status} options={STATUS_OPTIONS} onChange={v => { setStatus(v); setDrill(null); }} ariaLabel="Review status" />
            <label className="ai-search-field">
              <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>
              <input type="search" placeholder="Search company or prediction" aria-label="Search company or prediction"
                value={search} onChange={event => setSearch(event.target.value)} />
            </label>
            <button type="button" className="ui-control ai-reset" onClick={reset}>Reset</button>
          </div>
        </div>

        {loading?<p role="status" className="ai-scope-warning">Updating verified reporting for the selected filters…</p>:null}
        {scope !== "verified" ? (
          <p className="ai-scope-warning" role="note">{scopeNote}. These KPIs include non-verified populations and are not customer-only metrics.</p>
        ) : null}

        <section className="metrics-grid-section ed-section ai-kpi-section" aria-label="Bill extraction key metrics">
          <SectionHead title="At a glance" question="Volume, economics, performance and review outcomes" />
          <div className="ed-quality-kpis ed-kpi-grid po-kpis" role="group" aria-label="Bill extraction key metrics">
          <MetricCard label="Bills processed" period={periodLabel} value={String(kpis.bills)} note="predictions in scope"
            onDrill={() => openDrill("Bills processed", periodLabel + " · " + coverage, "all")} onInfo={() => setInfoKey("bills")} />
          <MetricCard label="Active companies" period={periodLabel} value={String(kpis.companies)} note="with extractions"
            onDrill={() => setCompanyDrill(true)} onInfo={() => setInfoKey("companies")} />
          <MetricCard label="Recorded AI cost" period={periodLabel} value={kpis.knownCostTotal.toFixed(1)} note={"cost units · " + kpis.unknownCostCount + " unknown excluded"}
            onDrill={() => openDrill("Recorded AI cost", periodLabel + " · " + coverage, "known_cost")} onInfo={() => setInfoKey("cost")} />
          <MetricCard label="Avg known cost / bill" period={periodLabel} value={kpis.avgKnownCost === null ? "—" : kpis.avgKnownCost.toFixed(3)} note={"cost units / bill · " + coverage}
            onDrill={() => openDrill("Average known cost", periodLabel + " · " + coverage, "all")} onInfo={() => setInfoKey("avg")} />
          <MetricCard label="P95 processing latency" period={periodLabel} value={kpis.p95Latency === null ? "—" : String(kpis.p95Latency)} note={"latency units · " + kpis.unknownLatencyCount + " unknown"}
            onDrill={() => openDrill("Slowest extractions", periodLabel + " · known latency only", "known_latency")} onInfo={() => setInfoKey("latency")} />
          <MetricCard label="Needs-review rate" period={periodLabel} value={kpis.needsReviewRate === null ? "—" : (kpis.needsReviewRate * 100).toFixed(1) + "%"} note={kpis.needsReviewCount + " of " + kpis.bills + " · snapshot"}
            onDrill={() => openDrill("Needs review", periodLabel + " · status snapshot", "needs_review")} onInfo={() => setInfoKey("review")} />
          </div>
        </section>

        <section className="metrics-grid-section ed-section" aria-label="Volume and cost trends">
          <SectionHead title="Processing & spend" question="What is moving, and what does it cost?" />
          <div className="ed-collection">
            <Surface title="Processing volume trend" subtitle="Recorded predictions by month" infoKey="bills" onInfo={setInfoKey} half>
              <MonthBars
                points={months.map(m => ({ month: m.month, value: m.bills }))}
                total={kpis.bills}
                emptyLabel="No extractions match these filters."
                onSelect={month => openDrill("Volume · " + month, scopeNote, "month", month)}
              />
            </Surface>
            <Surface title="AI cost trend" subtitle="Known cost per month · unknown excluded" infoKey="cost" onInfo={setInfoKey} half>
              <MonthBars
                points={months.map(m => ({ month: m.month, value: m.knownCost, note: m.unknownCostCount + " unknown" }))}
                total={kpis.knownCostCount}
                emptyLabel="No known-cost extractions match these filters."
                onSelect={month => openDrill("Cost · " + month, scopeNote, "month_cost", month)}
              />
            </Surface>
          </div>
          <div className="ed-collection">
            <Surface title="Extraction vs enrichment" subtitle="Recorded component costs · complete breakdowns" infoKey="cost" onInfo={setInfoKey} half>
              <ComponentBreakdown stats={data!.components} bills={kpis.bills} onOpen={kind => openDrill(kind === "extraction" ? "Extraction cost" : "Enrichment cost", periodLabel + " · complete breakdowns only", "components")} />
            </Surface>
            <Surface title="Processing latency" subtitle="Monthly P50 and P95 · known latency only" infoKey="latency" onInfo={setInfoKey} half>
              <LatencyComparison points={months} onSelect={month => openDrill("Latency · " + month, scopeNote, "month_latency", month)} />
            </Surface>
          </div>
        </section>

        <section className="metrics-grid-section ed-section" aria-label="Mix and review">
          <SectionHead title="Document outcomes" question="What is being processed and where is review needed?" />
          <div className="ed-collection">
            <Surface title="Document mix" subtitle="Share of predictions by input type" infoKey="bills" onInfo={setInfoKey} half>
              <DistributionRows rows={docs.map(d => ({ key: d.docType, label: d.docType, count: d.bills }))} total={kpis.bills}
                onSelect={type => openDrill("Document type · " + type, periodLabel, "doc_type", type)} />
            </Surface>
            <Surface title="Review outcomes" subtitle="Current status snapshot · not extraction accuracy" infoKey="review" onInfo={setInfoKey} half>
              <DistributionRows rows={reviews.map(r => ({ key: r.status, label: r.status.replaceAll("_", " "), count: r.bills }))} total={kpis.bills}
                onSelect={status => openDrill("Review status · " + status, periodLabel, "review_status", status)} />
            </Surface>
          </div>
          <div className="ed-collection">
            <Surface title="Legibility vs review needs" subtitle="Needs-review rate within each score bucket" infoKey="review" onInfo={setInfoKey} half>
              <LegibilityRows buckets={buckets} onSelect={bucket => openDrill("Legibility · " + bucket, periodLabel, "legibility", bucket)} />
            </Surface>
            <Surface title="Company consumption" subtitle="Top companies by volume" infoKey="companies" onInfo={setInfoKey} half>
              <MetricsInvestigationTable
                rows={companyRows.slice(0, 6).map(c => ({
                  id: c.companyUuid, label: c.companyName + (c.scope === "verified_customer" ? "" : " (" + c.scope + ")"), value: String(c.bills), detail: c.knownCost.toFixed(1) + " units known",
                  onOpen: () => openDrill("Extraction history · " + c.companyName, periodLabel, "company", c.companyUuid),
                }))}
                labelHeader="Company" valueHeader="Bills" detailHeader="Known cost" emptyMessage="No companies in scope." ariaLabel="Company consumption"
              />
              {companyRows.length > 6 ? <button type="button" className="ai-view-all-link"
                onClick={() => setCompanyDrill(true)}>View all {companyRows.length} companies →</button> : null}
            </Surface>
          </div>
        </section>

        <section className="metrics-grid-section ed-section" aria-label="Data quality">
          <SectionHead title="Data confidence" question="Where is the reporting incomplete?" />
          <Surface title="Data-quality exceptions" subtitle="Missing fields are unknown, never zero" infoKey="cost" onInfo={setInfoKey}>
            <MetricsInvestigationTable
              rows={exceptionRows}
              labelHeader="Exception" valueHeader="Records" detailHeader="Handling" emptyMessage="No exceptions in scope." ariaLabel="Data quality exceptions"
              fullTotal={{ label: "In scope", value: String(kpis.bills), detail: coverage }}
            />
          </Surface>
        </section>

        <footer className="ed-preview-note">
          <strong>Live Supabase reporting.</strong> Source loaded {data.asOf ? new Date(data.asOf).toLocaleString("en-IN",{timeZone:"Asia/Kolkata"}) + " IST" : "at an unknown time"}. Missing cost and latency are excluded from their respective calculations. Currency and latency units are not yet verified.
        </footer>
      </main>

      {companyDrill ? (
        <BillCompaniesModal companies={companyRows} scope={liveScope} bills={kpis.bills} coverage={coverage} period={periodLabel} onClose={() => setCompanyDrill(false)} />
      ) : null}
      {drill ? (
        <BillRecordsModal title={drill.title} subtitle={drill.subtitle} coverage={coverage} scope={liveScope} drillKind={drill.kind} drillValue={drill.value} onClose={() => setDrill(null)} />
      ) : null}
      {infoKey && INFO[infoKey] ? (
        <MetricsInfoDialog definition={INFO[infoKey]} onClose={() => setInfoKey(null)} sectionLabel="AI Services" />
      ) : null}
      <span className="ed-screenreader-only" aria-live="polite">Showing {kpis.bills} verified extraction records.</span>
    </div>
  );
}
