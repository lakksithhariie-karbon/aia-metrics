"use client";

import { useEffect, useRef, useState } from "react";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";

type Metric = "wau" | "mau" | "stickiness";
const numbers = new Intl.NumberFormat("en-US");

function change(current: number, previous: number): number | null {
  return previous > 0 ? (100 * (current - previous)) / previous : null;
}

function percent(numerator: number, denominator: number): string {
  return denominator > 0 ? ((100 * numerator) / denominator).toFixed(1) + "%" : "—";
}

const definitions: Record<Metric, { title: string; explanation: string; formula: string }> = {
  wau: {
    title: "Weekly core-active users",
    explanation:
      "Distinct users performing independent accounting work in the last 7 rolling days. Qualifying actions include bill/invoice uploads and creation, transaction edits and corrections. Accounting Sync is excluded because its events do not identify manual vs automatic execution. Failed activity, internal staff and non-client companies are excluded. Users count once across companies.",
    formula: "WAU = unique users with independent core work in [as-of − 7d, as-of)",
  },
  mau: {
    title: "Monthly core-active users",
    explanation:
      "Distinct users performing the same independent accounting actions as WAU, measured over the last 30 rolling days. Accounting Sync alone never makes a user active. Each user counts once even across several client companies.",
    formula: "MAU = unique users with independent core work in [as-of − 30d, as-of)",
  },
  stickiness: {
    title: "Stickiness",
    explanation:
      "Percentage of 30-day independent core-active users who also performed independent core accounting work in the last 7 days. WAU is a subset of MAU; both use the same source cutoff and eligibility rules.",
    formula: "Stickiness = WAU ÷ MAU × 100",
  },
};

export default function OverviewKpiStrip({
  snapshot,
}: {
  snapshot: OverviewUsageSnapshot | null;
}) {
  const [asOfDate, setAsOfDate] = useState(snapshot?.asOfDate ?? "");
  const [selected, setSelected] = useState<Metric>("wau");
  const dialog = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const onAsOf = (event: Event) => {
      const value = (event as CustomEvent<{ asOf: string }>).detail?.asOf;
      if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
        setAsOfDate(value);
      }
    };
    window.addEventListener("aia:overview-asof", onAsOf);
    return () => window.removeEventListener("aia:overview-asof", onAsOf);
  }, []);

  const current = Boolean(snapshot && asOfDate === snapshot.asOfDate);
  const note = snapshot
    ? "Historical KPIs are not published for this date"
    : "Live overview data temporarily unavailable";
  const wau = current && snapshot ? snapshot.wau.current : null;
  const mau = current && snapshot ? snapshot.mau.current : null;

  const cards: Array<{
    key: Metric;
    title: string;
    period: string;
    value: string;
    description: string;
    delta: number | null;
    comparison: string;
  }> = [
    {
      key: "wau",
      title: "Weekly core-active users",
      period: "Last 7 days",
      value: wau === null ? "—" : numbers.format(wau),
      description: current ? "Distinct users doing core work" : note,
      delta: current && snapshot ? change(snapshot.wau.current, snapshot.wau.previous) : null,
      comparison: "vs previous 7 days",
    },
    {
      key: "mau",
      title: "Monthly core-active users",
      period: "Last 30 days",
      value: mau === null ? "—" : numbers.format(mau),
      description: current ? "Distinct users doing core work" : note,
      delta: current && snapshot ? change(snapshot.mau.current, snapshot.mau.previous) : null,
      comparison: "vs previous 30 days",
    },
    {
      key: "stickiness",
      title: "Stickiness",
      period: "WAU / MAU",
      value: wau !== null && mau !== null ? percent(wau, mau) : "—",
      description:
        wau !== null && mau !== null
          ? numbers.format(wau) + " of " + numbers.format(mau) + " monthly-active users"
          : note,
      delta: null,
      comparison: "Also active in the last 7 days",
    },
  ];

  const open = (metric: Metric) => {
    setSelected(metric);
    dialog.current?.showModal();
  };

  const selectedCard = cards.find(card => card.key === selected);
  const detail = definitions[selected];

  return (
    <>
      {cards.map(card => (
        <button
          key={card.key}
          className="metric-card"
          type="button"
          onClick={() => open(card.key)}
          aria-haspopup="dialog"
          aria-controls="po-live-kpi-dialog"
          aria-label={card.title + ": " + card.value + ". View calculation and source."}
        >
          <span className="po-kpi-divider" aria-hidden="true" />
          <span className="metric-label">{card.title}</span>
          <span className="metric-period">{card.period}</span>
          <span className="metric-value">{card.value}</span>
          <span className="metric-note">{card.description}</span>
          {card.key === "stickiness" ? (
            <span className="po-change">Also active in the last 7 days</span>
          ) : card.delta === null ? (
            <span className="po-change">
              {current ? "No comparable preceding period" : "Latest published snapshot only"}
            </span>
          ) : (
            <span className="po-change">
              <svg className="icon" aria-hidden="true">
                <use href={card.delta < 0 ? "#i-down" : "#i-up"} />
              </svg>
              <strong className={card.delta < 0 ? "negative" : "positive"}>
                {card.delta > 0 ? "+" : ""}{card.delta.toFixed(1)}%
              </strong>
              <span>{card.comparison}</span>
            </span>
          )}
        </button>
      ))}

      <dialog
        ref={dialog}
        id="po-live-kpi-dialog"
        className="info-dialog po-live-kpi-dialog"
        aria-labelledby="po-live-kpi-title"
      >
        <header className="dialog-header">
          <div>
            <h2 className="dialog-title" id="po-live-kpi-title">{detail.title}</h2>
            <p className="dialog-subtitle">
              {current ? "Published production metric" : "Definition and data availability"}
            </p>
          </div>
          <button
            type="button"
            className="close-button"
            aria-label="Close metric details"
            onClick={() => dialog.current?.close()}
          >
            <svg className="icon" aria-hidden="true"><use href="#i-close" /></svg>
          </button>
        </header>
        <div className="info-body">
          <div className="definition-block">
            <h3>Calculation</h3>
            <p>{detail.explanation}</p>
            <div className="formula">{detail.formula}</div>
          </div>
          <div className="definition-block">
            <h3>Reporting window</h3>
            <p>
              {current && snapshot
                ? "Source-aligned counts through " +
                  new Date(snapshot.asOf).toLocaleString("en-GB", {
                    timeZone: "Asia/Kolkata",
                    dateStyle: "medium",
                    timeStyle: "short",
                  }) +
                  " IST. Period comparisons use the immediately preceding non-overlapping 7- or 30-day window."
                : "The selected historical reporting date has no published KPI generation. No prototype numbers are substituted."}
            </p>
            {current && snapshot && selected !== "stickiness" ? (
              <p className="po-kpi-detail-counts">
                Current: {selectedCard?.value} · Previous:{" "}
                {numbers.format(
                  selected === "wau" ? snapshot.wau.previous : snapshot.mau.previous,
                )}
              </p>
            ) : null}
            {current && snapshot && selected === "stickiness" ? (
              <p className="po-kpi-detail-counts">
                WAU: {numbers.format(snapshot.wau.current)} · MAU:{" "}
                {numbers.format(snapshot.mau.current)}
              </p>
            ) : null}
          </div>
        </div>
        <div className="info-footnote">
          {snapshot
            ? "Supabase overview snapshot #" +
              snapshot.snapshotId +
              " · Only events ingested by " +
              new Date(snapshot.sourceWatermarkAt).toLocaleString("en-GB", {
                timeZone: "Asia/Kolkata",
                dateStyle: "medium",
                timeStyle: "short",
              }) +
              " IST"
            : "Verified production data is unavailable."}
        </div>
      </dialog>
    </>
  );
}
