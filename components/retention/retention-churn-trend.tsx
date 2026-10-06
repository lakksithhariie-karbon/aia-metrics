"use client";

import React, { useMemo } from "react";
import type {
  RetentionChurnSeries,
  RetentionChurnSeriesRow,
} from "../../lib/retention/types";
import type { RetentionChurnSegment } from "../../lib/retention/drill-types";

const nf = new Intl.NumberFormat("en-US");

function monthLabel(month: string): string {
  return new Date(month + "-01T12:00:00Z")
    .toLocaleDateString("en-GB", {
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    })
    .replace("Sept", "Sep");
}

function deltaLabel(
  current: RetentionChurnSeriesRow,
  previous: RetentionChurnSeriesRow | undefined,
): string {
  if (
    !previous ||
    current.rate_pct == null ||
    previous.rate_pct == null
  ) {
    return "—";
  }
  const delta = current.rate_pct - previous.rate_pct;
  if (Math.abs(delta) < 0.05) return "0.0pp";
  return (delta > 0 ? "+" : "") + delta.toFixed(1) + "pp";
}

export default function RetentionChurnTrend({
  series,
  loading,
  onMonthClick,
}: {
  series: RetentionChurnSeries;
  loading?: boolean;
  onMonthClick: (
    row: RetentionChurnSeriesRow,
    segment?: RetentionChurnSegment,
  ) => void;
}) {
  const rows = series.rows;
  const latest = rows.at(-1) ?? null;

  const eligibleTotal = useMemo(
    () => rows.reduce((sum, row) => sum + row.eligible, 0),
    [rows],
  );

  return (
    <article className="report-card rd-churn-trend-report">
      <header className="report-header rd-churn-trend-head">
        <div>
          <h2>Month-on-Month Churn Trend</h2>
          <p className="report-subtitle">
            Completed monthly cohorts · each row opens that month&apos;s company list
          </p>
        </div>
        {loading ? (
          <span className="rd-churn-updating">Updating…</span>
        ) : null}
      </header>

      {latest ? (
        <section
          className="rd-churn-summary-strip"
          aria-label="Latest churn summary"
        >
          <button type="button" onClick={() => onMonthClick(latest, "all")}>
            <span>Latest rate</span>
            <strong>{latest.rate_pct?.toFixed(1) ?? "—"}%</strong>
            <small>{monthLabel(latest.month)}</small>
          </button>
          <button type="button" onClick={() => onMonthClick(latest, "entered")}>
            <span>Entered churn</span>
            <strong>{nf.format(latest.entered)}</strong>
            <small>during {monthLabel(latest.month).split(" ")[0]}</small>
          </button>
          <button
            type="button"
            onClick={() => onMonthClick(latest, "reactivated")}
          >
            <span>Reactivated</span>
            <strong>{nf.format(latest.reactivated)}</strong>
            <small>during {monthLabel(latest.month).split(" ")[0]}</small>
          </button>
        </section>
      ) : null}

      <div className="rd-churn-table-meta">
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
        </span>
      </div>

      {rows.length ? (
        <div className="rd-churn-table-wrap">
          <table className="rd-churn-table">
            <thead>
              <tr>
                <th scope="col">Month</th>
                <th scope="col">Churn rate</th>
                <th scope="col">vs prev</th>
                <th scope="col">Churned</th>
                <th scope="col">Eligible</th>
                <th scope="col">Entered</th>
                <th scope="col">Reactivated</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => {
                const delta = deltaLabel(row, rows[index - 1]);
                const rate = row.rate_pct ?? 0;
                return (
                  <tr
                    key={row.month}
                    className="rd-churn-table-row"
                    tabIndex={0}
                    role="button"
                    aria-label={
                      monthLabel(row.month) +
                      ": " +
                      rate.toFixed(1) +
                      "% churn. View company drill."
                    }
                    onClick={() => onMonthClick(row, "all")}
                    onKeyDown={event => {
                      if (event.key === "Enter" || event.key === " ") {
                        event.preventDefault();
                        onMonthClick(row, "all");
                      }
                    }}
                  >
                    <th scope="row">
                      <span className="rd-churn-month-link">
                        {monthLabel(row.month)}
                        <span aria-hidden="true">→</span>
                      </span>
                    </th>
                    <td>
                      <div className="rd-churn-rate-cell">
                        <strong>{rate.toFixed(1)}%</strong>
                        <span className="rd-churn-rate-track" aria-hidden="true">
                          <span style={{ width: Math.max(rate, 1) + "%" }} />
                        </span>
                      </div>
                    </td>
                    <td>
                      <span
                        className={
                          "rd-churn-delta " +
                          (delta.startsWith("+")
                            ? "is-up"
                            : delta.startsWith("-")
                              ? "is-down"
                              : "")
                        }
                      >
                        {delta}
                      </span>
                    </td>
                    <td>{nf.format(row.churned)}</td>
                    <td>{nf.format(row.eligible)}</td>
                    <td>
                      <button
                        type="button"
                        className="rd-churn-inline-link"
                        onClick={event => {
                          event.stopPropagation();
                          onMonthClick(row, "all");
                        }}
                        aria-label={
                          "Inspect entered churn for " + monthLabel(row.month)
                        }
                      >
                        {nf.format(row.entered)}
                      </button>
                    </td>
                    <td>
                      <button
                        type="button"
                        className="rd-churn-inline-link"
                        onClick={event => {
                          event.stopPropagation();
                          onMonthClick(row, "all");
                        }}
                        aria-label={
                          "Inspect reactivated companies for " +
                          monthLabel(row.month)
                        }
                      >
                        {nf.format(row.reactivated)}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="rd-churn-empty">
          <strong>No completed churn month in this range</strong>
          <p>Choose a range containing at least one completed calendar month.</p>
        </div>
      )}

      <footer className="report-footer rd-churn-trend-footer">
        <span>Eligible = activated before the month began</span>
        <span>
          Entered = newly churned · Reactivated = churned last month, active now
        </span>
      </footer>
    </article>
  );
}
