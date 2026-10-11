"use client";

import { useEffect, useId, useRef, useState } from "react";
import type { InfraAwsMonth, InfraAwsService, InfraAwsAccount } from "../../lib/infra/types";

const money = (n: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 2 }).format(n);
const labelMonth = (s: string) => new Date(s + "-01T12:00:00Z").toLocaleDateString("en-GB", { month: "short", year: "2-digit", timeZone: "UTC" }).replace("Sept", "Sep");
const shortService = (s: string) => ({
  "Amazon Relational Database Service": "Amazon RDS", "Amazon Elastic Container Service": "Amazon ECS",
  "Savings Plans for AWS Compute usage": "Savings Plans", "AmazonCloudWatch": "CloudWatch",
  "Amazon Elastic Load Balancing": "Load Balancing", "Amazon EC2 Container Registry (ECR)": "Amazon ECR",
  "Amazon Virtual Private Cloud": "Amazon VPC", "Amazon Simple Storage Service": "Amazon S3", "Amazon ElastiCache": "ElastiCache",
} as Record<string, string>)[s] ?? s;

function smoothPath(points: { x: number; y: number }[]): string {
  if (!points.length) return "";
  let d = "M " + points[0].x + " " + points[0].y;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1], b = points[i], mid = (a.x + b.x) / 2;
    d += " C " + mid + " " + a.y + ", " + mid + " " + b.y + ", " + b.x + " " + b.y;
  }
  return d;
}

/** Measure the actual report interior: no fixed-ratio SVG letterboxing. */
export function AwsSpendTrend({ months, selected, onSelect }: {
  months: InfraAwsMonth[]; selected: string; onSelect: (month: string) => void;
}) {
  const id = "infra-spend-" + useId().replace(/:/g, "");
  const host = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(940);
  const [hover, setHover] = useState<string | null>(null);
  useEffect(() => {
    const element = host.current;
    if (!element) return;
    const measure = () => setWidth(Math.max(240, Math.floor(element.getBoundingClientRect().width)));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  if (!months.length) return <div className="infra-chart-empty">No captured monthly observations in this range.</div>;
  const height = 270, left = 49, right = 17, top = 20, bottom = 35;
  const base = height - bottom, plotHeight = base - top, plotWidth = width - left - right;
  const largest = Math.max(1, ...months.map(m => m.usd));
  const step = Math.max(100, Math.ceil(largest / 5 / 100) * 100);
  const tickCount = Math.ceil(largest / step), maximum = tickCount * step;
  const points = months.map((m, index) => ({
    ...m, x: left + (months.length === 1 ? plotWidth / 2 : index * plotWidth / (months.length - 1)),
    y: base - m.usd / maximum * plotHeight,
  }));
  const active = months.find(m => m.month === (hover ?? selected)) ?? months[months.length - 1];
  const line = smoothPath(points);
  const area = line + " L " + points[points.length - 1].x + " " + base + " L " + points[0].x + " " + base + " Z";
  const slot = months.length > 1 ? plotWidth / (months.length - 1) : plotWidth;
  return <div className="infra-chart-shell">
    <div ref={host} className="infra-trend-viewport">
      <svg viewBox={"0 0 " + width + " " + height} className="infra-svg-chart" role="group" aria-label="AWS monthly cost trend; select a point to inspect its month">
        <defs><linearGradient id={id} x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor="#5276d9" stopOpacity=".2" /><stop offset="100%" stopColor="#5276d9" stopOpacity=".012" /></linearGradient></defs>
        {Array.from({ length: tickCount + 1 }, (_, i) => {
          const value = i * step, y = base - value / maximum * plotHeight;
          const text = value === 0 ? "0" : value < 1000 ? "$" + value : "$" + (value / 1000).toLocaleString("en-US", { maximumFractionDigits: 1 }) + "k";
          return <g key={value}><path d={"M " + left + " " + y + " H " + (width - right)} stroke="#e9edf5" strokeDasharray={i ? "3 5" : undefined} />
            <text x={left - 10} y={y + 3} textAnchor="end" className="infra-axis-label">{text}</text></g>;
        })}
        <path d={area} fill={"url(#" + id + ")"} />
        <path d={line} fill="none" stroke="#365fd3" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
        {points.map(p => {
          const marked = p.month === (hover ?? selected);
          const hitLeft = Math.max(left, p.x - slot / 2), hitRight = Math.min(width - right, p.x + slot / 2);
          return <g key={p.month} role="button" tabIndex={0}
            aria-label={labelMonth(p.month) + ": " + money(p.usd) + (p.estimated ? ", estimated" : "") + ". View month breakdown."}
            onMouseEnter={() => setHover(p.month)} onMouseLeave={() => setHover(null)} onFocus={() => setHover(p.month)} onBlur={() => setHover(null)}
            onClick={() => onSelect(p.month)} onKeyDown={e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelect(p.month); } }}>
            <rect className="infra-point-hit" x={hitLeft} y={top} width={Math.max(1, hitRight - hitLeft)} height={plotHeight} fill="transparent" />
            {marked ? <path d={"M " + p.x + " " + top + " V " + base} stroke="#8da7ea" strokeDasharray="4 5" /> : null}
            {marked ? <circle cx={p.x} cy={p.y} r="9" fill="#e6edff" /> : null}
            <circle cx={p.x} cy={p.y} r={marked ? 4.5 : 3} fill="#fff" stroke="#365fd3" strokeWidth={marked ? 2.6 : 1.8} />
            <text x={p.x} y={base + 23} textAnchor="middle" className={"infra-axis-label" + (marked ? " is-active" : "")}>{labelMonth(p.month).split(" ")[0]}</text>
            <title>{labelMonth(p.month)} · {money(p.usd)}{p.estimated ? " · estimated" : ""}</title>
          </g>;
        })}
      </svg>
    </div>
    <div className="infra-chart-summary">
      <div><span>{labelMonth(active.month)} AWS spend</span><strong>{money(active.usd)}</strong></div>
      <div><span>Reporting</span><strong>{active.estimated ? "Estimated · partial month" : "Completed month"}</strong></div>
      <span className="infra-chart-hint">Select a month to inspect its breakdown</span>
    </div>
  </div>;
}

type CostRow = { key: string; label: string; usd: number };

/** One table component for both cost drivers and linked accounts. */
function CostBreakdownTable({ rows, total, dimension, otherLabel, onSelect }: {
  rows: CostRow[]; total: number; dimension: string; otherLabel: string; onSelect: (key: string) => void;
}) {
  const shown = [...rows].sort((a, b) => b.usd - a.usd || a.label.localeCompare(b.label)).slice(0, 7);
  const remainder = Math.max(0, total - shown.reduce((sum, r) => sum + r.usd, 0));
  const share = (amount: number) => total > 0 ? amount / total * 100 : 0;
  const shareCell = (amount: number) => <div className="infra-share-cell">
    <span className="infra-share-track" aria-hidden="true"><i style={{ width: Math.min(100, share(amount)) + "%" }} /></span>
    <span>{share(amount).toFixed(1)}%</span>
  </div>;
  return <div className="ed-table-shell infra-breakdown-shell">
    <table className="ed-report-table infra-breakdown-table">
      <colgroup><col className="infra-dimension-col" /><col className="infra-amount-col" /><col className="infra-share-col" /></colgroup>
      <thead><tr><th scope="col">{dimension}</th><th scope="col" className="infra-number">Spend (USD)</th><th scope="col" className="infra-number">Share</th></tr></thead>
      <tbody>
        {shown.map(r => <tr key={r.key}>
          <th scope="row"><button type="button" className="ed-cell-drill infra-dimension-link" onClick={() => onSelect(r.key)} aria-label={r.label + ", " + money(r.usd) + ". View breakdown."} title={r.label}>{r.label}</button></th>
          <td className="infra-number">{money(r.usd)}</td><td>{shareCell(r.usd)}</td>
        </tr>)}
        <tr className="infra-other-row"><th scope="row" title="The monthly total less the seven displayed rows; includes uncaptured detail">{otherLabel}</th><td className="infra-number">{money(remainder)}</td><td>{shareCell(remainder)}</td></tr>
      </tbody>
      <tfoot><tr><th scope="row">Total</th><td className="infra-number">{money(total)}</td><td className="infra-number">{total > 0 ? "100.0%" : "0.0%"}</td></tr></tfoot>
    </table>
  </div>;
}

export function ServiceDrivers({ rows, total, month, onSelect }: {
  rows: InfraAwsService[]; total: number; month: string; onSelect: (service: string) => void;
}) {
  if (!rows.length) return <div className="infra-chart-empty">Service breakdowns in this preview begin in May 2026.</div>;
  return <CostBreakdownTable rows={rows.map(r => ({ key: r.service, label: shortService(r.service), usd: r.usd }))}
    total={total} dimension="Service / category" otherLabel="Other categories" onSelect={onSelect} />;
}

export function AccountDistribution({ rows, total, onSelect }: {
  rows: InfraAwsAccount[]; total: number; onSelect: (name: string) => void;
}) {
  if (!rows.length) return <div className="infra-chart-empty">Account breakdowns in this preview begin in May 2026.</div>;
  return <CostBreakdownTable rows={rows.map(r => ({ key: r.label, label: r.label, usd: r.usd }))}
    total={total} dimension="AWS account" otherLabel="Other accounts" onSelect={onSelect} />;
}
