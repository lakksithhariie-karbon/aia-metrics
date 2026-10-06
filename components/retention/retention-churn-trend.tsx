"use client";

import React, { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import type {
  RetentionChurnSeries,
  RetentionChurnSeriesRow,
} from "../../lib/retention/types";

const nf = new Intl.NumberFormat("en-US");

interface TooltipState {
  rect: DOMRect;
  row: RetentionChurnSeriesRow;
}

function monthLabel(month: string): string {
  return new Date(month + "-01T12:00:00Z")
    .toLocaleDateString("en-GB", {
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    })
    .replace("Sept", "Sep");
}

function ChurnTooltip({ value }: { value: TooltipState | null }) {
  if (!value || typeof document === "undefined") return null;

  const width = 228;
  const margin = 12;
  const left = Math.max(
    margin,
    Math.min(
      value.rect.left + value.rect.width / 2 - width / 2,
      window.innerWidth - width - margin,
    ),
  );
  const placeAbove = value.rect.top > 170;
  const top = placeAbove ? value.rect.top - 8 : value.rect.bottom + 8;
  const rate = value.row.rate_pct ?? 0;

  return createPortal(
    <div
      className={
        "rd-churn-tooltip " + (placeAbove ? "is-above" : "is-below")
      }
      role="tooltip"
      style={{ left, top, width }}
    >
      <div className="rd-churn-tooltip-eyebrow">
        {monthLabel(value.row.month)}
      </div>
      <div className="rd-churn-tooltip-value">
        {rate.toFixed(1)}%
        <span>monthly churn</span>
      </div>
      <div className="rd-churn-tooltip-stats">
        <span>
          <strong>{nf.format(value.row.churned)}</strong>
          Churned
        </span>
        <span>
          <strong>{nf.format(value.row.active)}</strong>
          Active
        </span>
        <span>
          <strong>{nf.format(value.row.eligible)}</strong>
          Eligible
        </span>
      </div>
      <div className="rd-churn-tooltip-hint">
        Click to inspect companies & users
      </div>
    </div>,
    document.body,
  );
}

export default function RetentionChurnTrend({
  series,
  loading,
  onMonthClick,
}: {
  series: RetentionChurnSeries;
  loading?: boolean;
  onMonthClick: (row: RetentionChurnSeriesRow) => void;
}) {
  const [tooltip, setTooltip] = useState<TooltipState | null>(null);

  useEffect(() => {
    if (!tooltip) return;
    const hide = () => setTooltip(null);
    window.addEventListener("resize", hide);
    window.addEventListener("scroll", hide, true);
    return () => {
      window.removeEventListener("resize", hide);
      window.removeEventListener("scroll", hide, true);
    };
  }, [tooltip]);

  const rows = series.rows;
  const eligibleTotal = useMemo(
    () => rows.reduce((sum, row) => sum + row.eligible, 0),
    [rows],
  );
  const latest = rows.at(-1) ?? null;

  return (
    <>
      <article className="report-card rd-churn-trend-report">
        <header className="report-header rd-churn-trend-head">
          <div>
            <h2>Monthly churn</h2>
            <p className="report-subtitle">
              Activated companies with no non-failed core activity in completed calendar months
            </p>
          </div>
          {latest ? (
            <div className="rd-churn-latest">
              <span>Latest · {monthLabel(latest.month)}</span>
              <strong>{latest.rate_pct?.toFixed(1) ?? "—"}%</strong>
            </div>
          ) : null}
        </header>

        <div className="report-toolbar rd-churn-trend-summary">
          <span>
            <strong>
              {rows.length} completed {rows.length === 1 ? "month" : "months"}
            </strong>
            {rows.length ? (
              <>
                {" "}
                <span aria-hidden="true">·</span>{" "}
                {nf.format(eligibleTotal)} eligible company-months
              </>
            ) : null}
            {loading ? <em>Updating…</em> : null}
          </span>
        </div>

        {rows.length ? (
          <div
            className="rd-churn-chart"
            role="region"
            aria-label="Monthly churn trend"
          >
            <div className="rd-churn-y-axis" aria-hidden="true">
              <span>100%</span>
              <span>75%</span>
              <span>50%</span>
              <span>25%</span>
              <span>0%</span>
            </div>

            <div className="rd-churn-plot">
              {[100, 75, 50, 25, 0].map(value => (
                <i
                  key={value}
                  className="rd-churn-grid-line"
                  style={{ bottom: value + "%" }}
                  aria-hidden="true"
                />
              ))}

              <div
                className="rd-churn-bars"
                style={{
                  gridTemplateColumns: `repeat(${Math.max(
                    rows.length,
                    1,
                  )}, minmax(58px, 1fr))`,
                }}
              >
                {rows.map(row => {
                  const rate = row.rate_pct ?? 0;
                  return (
                    <button
                      key={row.month}
                      type="button"
                      className="rd-churn-bar-button"
                      aria-label={`${monthLabel(row.month)}: ${rate.toFixed(
                        1,
                      )}% churn, ${row.churned} churned and ${row.active} active out of ${row.eligible}. View companies and users.`}
                      onMouseEnter={event =>
                        setTooltip({
                          rect: event.currentTarget.getBoundingClientRect(),
                          row,
                        })
                      }
                      onMouseLeave={() => setTooltip(null)}
                      onFocus={event =>
                        setTooltip({
                          rect: event.currentTarget.getBoundingClientRect(),
                          row,
                        })
                      }
                      onBlur={() => setTooltip(null)}
                      onClick={() => onMonthClick(row)}
                    >
                      <span className="rd-churn-bar-value">
                        {rate.toFixed(1)}%
                      </span>
                      <span className="rd-churn-bar-track">
                        <span
                          className="rd-churn-bar-fill"
                          style={{ height: Math.max(rate, 1) + "%" }}
                        />
                      </span>
                      <span className="rd-churn-bar-month">
                        {monthLabel(row.month)}
                      </span>
                      <span className="rd-churn-bar-fraction">
                        {nf.format(row.churned)}/{nf.format(row.eligible)} churned
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
        ) : (
          <div className="rd-churn-empty">
            <strong>No completed churn month in this range</strong>
            <p>Choose a range containing at least one completed calendar month.</p>
          </div>
        )}

        <footer className="report-footer rd-churn-trend-footer">
          <span>
            Eligible = activated before the month began
          </span>
          <span>
            Click a month to inspect churned and active companies
          </span>
        </footer>
      </article>

      <ChurnTooltip value={tooltip} />
    </>
  );
}
