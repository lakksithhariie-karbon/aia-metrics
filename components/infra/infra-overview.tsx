"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import ProductMonthRangePicker from "../ui/product-month-range-picker";
import MetricsInfoDialog, { MetricsInfoButton } from "../ui/metrics-info";
import MetricsInvestigationTable from "../ui/metrics-investigation-table";
import type { MetricsInfoDefinition } from "../ui/metrics-info";
import type { InfraPreviewData } from "../../lib/infra/types";
import { completedPreset, monthLabel, rangeLabel, resolveRange } from "../../lib/infra/date-range";
import type { MonthRange } from "../../lib/infra/date-range";
import { AwsSpendTrend, ServiceDrivers, AccountDistribution } from "./infra-charts";

type DrillKind = "aws-month" | "services" | "service" | "accounts" | "account";
type Drill = { kind: DrillKind; key?: string; month?: string };
type Metric = { id: string; label: string; value: string; period: string; caption: string; definition: string; drill: Drill };
type DrillRow = { label: string; amount: string; extra: string; drill?: Drill };
const us = (n: number) => new Intl.NumberFormat("en-US").format(n);
const usd = (n: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n);
const pct = (n: number) => n.toFixed(1) + "%";
const pretty = (v: string) => ({
  "Amazon Relational Database Service": "Amazon RDS", "Savings Plans for AWS Compute usage": "Savings Plans",
  "Amazon Elastic Container Service": "Amazon ECS", "AmazonCloudWatch": "CloudWatch",
  "Amazon Elastic Load Balancing": "Load Balancing", "Amazon EC2 Container Registry (ECR)": "Amazon ECR", "Amazon Virtual Private Cloud": "Amazon VPC",
} as Record<string, string>)[v] ?? v;
const previewDisclosure = "Captured AWS data as of 8 Oct 2026. This preview is not a live billing feed. October amounts are incomplete estimates.";

function SectionHead({ title, question }: { title: string; question: string }) {
  return <div className="metrics-section-kicker ed-section-heading"><span>{title}</span><span className="metrics-section-description">{question}</span></div>;
}

function Surface({ title, subtitle, children, half = false, onInfo }: {
  title: string; subtitle: string; children: ReactNode; half?: boolean; onInfo?: () => void;
}) {
  return <article className={"report-card ed-report" + (half ? " ed-report-half" : "")}>
    <header className="report-header ed-report-heading"><div><h2>{title}</h2><p className="report-subtitle">{subtitle}</p></div>
      {onInfo ? <MetricsInfoButton label={"How " + title + " is counted"} onClick={onInfo} /> : null}</header>
    {children}
  </article>;
}

function MetricCard({ metric, onDrill, onInfo }: { metric: Metric; onDrill: (drill: Drill) => void; onInfo: (metric: Metric) => void }) {
  return <div className="ed-metric-wrap">
    <button className="metric-card ed-metric" type="button" onClick={() => onDrill(metric.drill)} aria-haspopup="dialog" aria-label={metric.label + ": " + metric.value + ". Open supporting breakdown."}>
      <span className="po-kpi-divider" aria-hidden="true" /><span className="metric-label">{metric.label}</span>
      <span className="metric-period">{metric.period}</span><span className="metric-value">{metric.value}</span><span className="metric-note">{metric.caption}</span>
    </button>
    <MetricsInfoButton className="ed-info-button" label={"How " + metric.label + " is calculated"} onClick={() => onInfo(metric)} />
  </div>;
}

function BreakdownDialog({ target, month, data, onClose, onNext }: {
  target: Drill; month: string; data: InfraPreviewData; onClose: () => void; onNext: (target: Drill) => void;
}) {
  const closeRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLElement>(null);
  const [query, setQuery] = useState("");
  useEffect(() => {
    const before = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus({ preventScroll: true });
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); onClose(); return; }
      if (event.key !== "Tab") return;
      const all = Array.from(panelRef.current?.querySelectorAll<HTMLElement>('button:not([disabled]),a[href],[tabindex]:not([tabindex="-1"])') || []);
      if (!all.length) return;
      if (event.shiftKey && document.activeElement === all[0]) { event.preventDefault(); all[all.length - 1].focus(); }
      else if (!event.shiftKey && document.activeElement === all[all.length - 1]) { event.preventDefault(); all[0].focus(); }
    };
    document.addEventListener("keydown", onKey, true);
    return () => { document.body.style.overflow = before; document.removeEventListener("keydown", onKey, true); };
  }, [onClose]);

  const aws = data.awsMonths.find(x => x.month === month);
  const services = data.awsServices.filter(x => x.month === month);
  const accounts = data.awsAccounts.filter(x => x.month === month);
  let title = "", subtitle = "", note = "", rows: DrillRow[] = [];
  if (target.kind === "aws-month" || target.kind === "services") {
    title = (target.kind === "aws-month" ? "AWS spend · " : "Cloud services · ") + monthLabel(month);
    subtitle = "USD · " + (aws?.estimated ? "Estimated period" : "Completed month");
    rows = services.map(r => ({ label: pretty(r.service), amount: usd(r.usd), extra: pct(aws?.usd ? r.usd / aws.usd * 100 : 0), drill: { kind: "service", key: r.service, month } }));
    const other = Math.max(0, (aws?.usd ?? 0) - services.reduce((s, r) => s + r.usd, 0));
    if (services.length && other > .005) rows.push({ label: "Other categories", amount: usd(other), extra: "Combined" });
    note = services.length ? "The preview itemizes the eleven largest categories; other categories are included in the total." : "Only the month total is captured before May 2026. No service detail is available in this preview.";
  } else if (target.kind === "accounts") {
    title = "Linked AWS accounts · " + monthLabel(month);
    subtitle = "Masked account labels · USD";
    rows = accounts.map(r => ({ label: r.label, amount: usd(r.usd), extra: pct(aws?.usd ? r.usd / aws.usd * 100 : 0), drill: { kind: "account", key: r.label, month } }));
    const other = Math.max(0, (aws?.usd ?? 0) - accounts.reduce((s, r) => s + r.usd, 0));
    if (accounts.length && other > .005) rows.push({ label: "Other accounts", amount: usd(other), extra: "Combined" });
    note = accounts.length ? "Full AWS account IDs are masked. This preview captures the nine largest accounts per month." : "Only the month total is captured before May 2026. No account detail is available in this preview.";
  } else {
    const isService = target.kind === "service";
    title = isService ? pretty(target.key ?? "Service") : target.key ?? "AWS account";
    subtitle = "Captured monthly costs · USD";
    rows = data.awsMonths.filter(m => m.month >= "2026-05").map(m => {
      const item = isService ? data.awsServices.find(s => s.month === m.month && s.service === target.key) : data.awsAccounts.find(a => a.month === m.month && a.label === target.key);
      return { label: monthLabel(m.month), amount: item ? usd(item.usd) : "—", extra: item ? m.estimated ? "Estimated" : "Completed" : "Not captured" };
    });
    note = "A dash indicates detail outside the captured monthly top categories or accounts. It does not mean zero spend.";
  }

  // One Product / Engineering-style table for every Infra drill type.
  // Search only narrows the displayed rows; it never changes the month total.
  const search = query.trim().toLocaleLowerCase("en-US");
  const visible = search ? rows.filter(r =>
    [r.label,r.amount,r.extra].some(v => v.toLocaleLowerCase("en-US").includes(search))) : rows;
  const isMonthlyBreakdown =
    target.kind === "aws-month" || target.kind === "services" || target.kind === "accounts";
  const valueHeader = "Spend (USD)";
  const detailHeader = isMonthlyBreakdown ? "Share of month" : "Coverage";
  const monthlyTotal = isMonthlyBreakdown && rows.length && aws ? {
    label:"Full month total",value:usd(aws.usd),detail:"100.0%",
  } : undefined;
  const tableRows = visible.map((r,i) => ({
    id:r.label+":"+i,label:r.label,value:r.amount,detail:r.extra,
    muted:r.label.startsWith("Other "),onOpen:r.drill?()=>onNext(r.drill!):undefined,
  }));
  return <div className="ed-overlay" role="presentation"
    onMouseDown={e => {if(e.target===e.currentTarget)onClose();}}>
    <section ref={panelRef}
      className="rd-modal rd-activation-modal ed-investigation-modal infra-drill-dialog"
      role="dialog" aria-modal="true" aria-labelledby="infra-drill-title">
      <header className="rd-modal-head ed-investigation-head">
        <div>
          <p>Infrastructure · Cost breakdown</p>
          <h2 id="infra-drill-title">{title}</h2>
          <span>{subtitle}</span>
        </div>
        <button ref={closeRef} className="rd-close ed-investigation-close"
          type="button" onClick={onClose} aria-label="Close cost breakdown">×</button>
      </header>
      <div className="rd-drill-toolbar ed-investigation-toolbar">
        <div className="rd-search ed-investigation-search">
          <svg className="rd-icon" viewBox="0 0 24 24" aria-hidden="true"
            fill="none" stroke="currentColor" strokeWidth="1.7">
            <circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/>
          </svg>
          <input type="search" value={query}
            onChange={e=>setQuery(e.currentTarget.value)}
            aria-label="Search cost breakdown"
            placeholder={isMonthlyBreakdown?"Search service or account...":"Search reporting months..."} />
          {query?<button type="button" aria-label="Clear search"
            onClick={()=>setQuery("")}>×</button>:null}
        </div>
        <span className="infra-drill-toolbar-context">
          {isMonthlyBreakdown?"Selected month · "+monthLabel(month):"Captured monthly history"}
        </span>
      </div>
      <div className="ed-investigation-caption">
        <span>{isMonthlyBreakdown?"Ranked AWS cost breakdown":"Monthly history · missing detail is not zero"}</span>
        <span>{visible.length} of {rows.length} rows</span>
      </div>
      <MetricsInvestigationTable
        labelHeader={target.kind==="accounts"?"Linked account":
          target.kind==="service"||target.kind==="account"?"Month":"Service / category"}
        valueHeader={valueHeader} detailHeader={detailHeader}
        rows={tableRows} fullTotal={monthlyTotal}
        ariaLabel={title+" cost breakdown"}
        emptyMessage={rows.length
          ?"No rows match this search."
          :"This month has no captured service or account breakdown."}/>
      <footer className="rd-modal-foot rd-modal-foot-paginated ed-investigation-foot infra-drill-foot">
        <div className="rd-table-summary">
          <span>{note}</span>
          <small>{visible.length} displayed · {rows.length} source rows</small>
        </div>
      </footer>
    </section>
  </div>;
}

export default function InfraOverview({ data }: { data: InfraPreviewData }) {
  const [range, setRange] = useState<MonthRange>(() => completedPreset("6", data.awsAsOf));
  const [drill, setDrill] = useState<Drill | null>(null);
  const [info, setInfo] = useState<MetricsInfoDefinition | null>(null);
  const opener = useRef<HTMLElement | SVGElement | null>(null);
  const scope = useMemo(() => resolveRange(range, data.awsMonths.map(m => m.month)), [range, data.awsMonths]);
  const month = scope.end;
  const current = data.awsMonths.find(m => m.month === month);
  const index = data.awsMonths.findIndex(m => m.month === month);
  const previous = index > 0 ? data.awsMonths[index - 1] : null;
  const services = data.awsServices.filter(r => r.month === month);
  const accounts = data.awsAccounts.filter(r => r.month === month);
  const trend = data.awsMonths.filter(m => m.month >= scope.start && m.month <= scope.end);
  const difference = current && !current.estimated && previous && !previous.estimated && previous.usd > 0 ? (current.usd - previous.usd) / previous.usd * 100 : null;
  const period = monthLabel(month);
  const applyRange = (next: MonthRange) => { setDrill(null); setInfo(null); setRange(next); };
  const closeDrill = useCallback(() => { setDrill(null); requestAnimationFrame(() => opener.current?.focus({ preventScroll: true })); }, []);
  const openDrill = (target: Drill) => {
    opener.current = document.activeElement instanceof HTMLElement || document.activeElement instanceof SVGElement ? document.activeElement : null;
    setDrill({ ...target, month: target.month ?? month });
  };
  const metrics: Metric[] = [
    { id: "aws-cost", label: "AWS cloud spend", value: current ? usd(current.usd) : "—", period,
      caption: current?.estimated ? "Estimated month-to-date · USD" : "Monthly UnblendedCost · USD",
      definition: "Sum of all AWS Cost Explorer UnblendedCost in the end month selected in the date picker. Includes tax and Savings Plans. The range start changes the trend, not this monthly total.", drill: { kind: "aws-month" } },
    { id: "mom", label: "Month-on-month", value: difference === null ? "—" : (difference > 0 ? "+" : "") + pct(difference), period,
      caption: current?.estimated ? "Incomplete months are not compared" : "Compared with the previous completed month",
      definition: "Change in end-month AWS spend relative to its preceding completed month. No comparison is shown for incomplete or missing periods.", drill: { kind: "aws-month" } },
    { id: "accounts", label: "Linked AWS accounts", value: current ? us(current.accounts) : "—", period,
      caption: "Distinct linked accounts with cost rows",
      definition: "Distinct linked accounts recorded for the selected end month. Multi-month account counts are not summed. Account identifiers are masked in this preview.", drill: { kind: "accounts" } },
    { id: "services", label: "Cost categories", value: current ? us(current.services) : "—", period,
      caption: "Services, taxes and commitments",
      definition: "Distinct Cost Explorer service dimensions in the selected end month, including financial categories. Multi-month category counts are not summed.", drill: { kind: "services" } },
  ];
  const openInfo = (metric: Metric) => setInfo({ title: metric.label, logic: metric.definition, example: metric.caption, note: previewDisclosure });
  const reportInfo = (title: string, logic: string) => setInfo({ title, logic, example: "Select a value to inspect the captured cost breakdown.", note: previewDisclosure });
  return <>
    <main className="rd-page ed-page infra-page">
      <div className="rd-page-head ed-page-head"><div className="ed-page-copy">
        <div className="ed-titleline"><h1>Infrastructure Overview</h1></div><p>AWS cloud spending and cost drivers</p>
      </div><ProductMonthRangePicker value={range} asOf={data.awsAsOf} firstMonth={data.awsMonths[0].month} onApply={applyRange} /></div>
      <section className="metrics-grid-section ed-section" aria-label="AWS cloud spending">
        <SectionHead title="AWS cloud spending" question="Where is spend concentrated, and how is it changing?" />
        <div className="ed-sprint-kpis ed-kpi-grid po-kpis">{metrics.map(metric => <MetricCard key={metric.id} metric={metric} onDrill={openDrill} onInfo={openInfo} />)}</div>
        <div className="ed-collection">
          <Surface title="Cloud cost trajectory" subtitle={"Monthly AWS spend · USD · " + rangeLabel(range)} onInfo={() => reportInfo("Cloud cost trajectory", "Start and end months bound the visible cost trend. KPI cards and breakdown tables use the selected end month. Selecting a point opens that month's detail without changing the date range.")}>
            <AwsSpendTrend months={trend} selected={month} onSelect={selectedMonth => openDrill({ kind: "aws-month", month: selectedMonth })} />
          </Surface>
          <Surface half title="Top cost drivers" subtitle={"Largest categories · " + period} onInfo={() => reportInfo("Top cost drivers", "The seven largest captured service/category amounts for the end month. Other categories equals the overall monthly cost less those seven rows. Shares use the full monthly total.")}>
            <ServiceDrivers rows={services} total={current?.usd ?? 0} month={month} onSelect={key => openDrill({ kind: "service", key })} />
          </Surface>
          <Surface half title="Linked account distribution" subtitle={"Largest accounts · " + period} onInfo={() => reportInfo("Linked account distribution", "The seven largest captured linked accounts for the end month. Other accounts includes all remaining recorded account spend. Labels are masked; shares use the full monthly total.")}>
            <AccountDistribution rows={accounts} total={current?.usd ?? 0} onSelect={key => openDrill({ kind: "account", key })} />
          </Surface>
        </div>
      </section>
    </main>
    {info ? <MetricsInfoDialog definition={info} onClose={() => setInfo(null)} sectionLabel="Infrastructure Metrics" /> : null}
    {drill ? <BreakdownDialog key={drill.kind + ":" + (drill.key ?? "") + ":" + drill.month} target={drill} month={drill.month ?? month} data={data} onClose={closeDrill} onNext={next => setDrill({ ...next, month: next.month ?? drill.month })} /> : null}
  </>;
}
