"use client";

import React, { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import CompactMenuSelect from "../ui/compact-menu-select";
import type {
  RetentionHeatmapInterval,
  RetentionHeatmapResponse,
  RetentionHeatmapRow,
} from "../../lib/retention/types";

const nf = new Intl.NumberFormat("en-US");

const INTERVAL_OPTIONS = [
  { value: "weekly", label: "Weekly" },
  { value: "monthly", label: "Monthly" },
] as const;

export interface RetentionHeatmapTarget {
  interval: RetentionHeatmapInterval;
  cohortStart: string | null;
  relativePeriod: number;
  retained: number;
  denominator: number;
  label: string;
  pooled: boolean;
}

interface TooltipState {
  rect: DOMRect;
  label: string;
  period: string;
  index: number;
  retained: number;
  denominator: number;
}

function cohortLabel(
  value: string,
  interval: RetentionHeatmapInterval,
): string {
  const date = new Date(value.slice(0, 10) + "T12:00:00Z");
  return date
    .toLocaleDateString("en-GB", {
      ...(interval === "weekly" ? { day: "numeric" as const } : {}),
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    })
    .replace("Sept", "Sep");
}

function cellStyle(retained: number, denominator: number): React.CSSProperties {
  const ratio = denominator > 0 ? retained / denominator : 0;
  const start = [239, 244, 255];
  const end = [29, 78, 216];
  const rgb = start.map((value, index) =>
    Math.round(value + (end[index] - value) * ratio),
  );
  const linear = rgb.map(value => {
    const sample = value / 255;
    return sample <= 0.04045
      ? sample / 12.92
      : ((sample + 0.055) / 1.055) ** 2.4;
  });
  const luminance =
    0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  return {
    background: `rgb(${rgb.join(",")})`,
    color: luminance < 0.2 ? "#fff" : "#203050",
  };
}

function HeatmapTooltip({
  value,
}: {
  value: TooltipState | null;
}) {
  if (!value || typeof document === "undefined") return null;

  const width = 226;
  const margin = 12;
  const left = Math.max(
    margin,
    Math.min(
      value.rect.left + value.rect.width / 2 - width / 2,
      window.innerWidth - width - margin,
    ),
  );
  const placeAbove = value.rect.top > 150;
  const top = placeAbove ? value.rect.top - 8 : value.rect.bottom + 8;
  const churned = value.denominator - value.retained;
  const percent =
    value.denominator > 0
      ? (100 * value.retained) / value.denominator
      : 0;

  return createPortal(
    <div
      className={
        "rd-heat-tooltip " +
        (placeAbove ? "is-above" : "is-below")
      }
      role="tooltip"
      style={{ left, top, width }}
    >
      <div className="rd-heat-tooltip-eyebrow">
        {value.label} · {value.period} {value.index}
      </div>
      <div className="rd-heat-tooltip-value">
        {percent.toFixed(1)}%
        <span>retention</span>
      </div>
      <div className="rd-heat-tooltip-stats">
        <span>
          <strong>{nf.format(value.retained)}</strong>
          Retained
        </span>
        <span>
          <strong>{nf.format(churned)}</strong>
          Churned
        </span>
        <span>
          <strong>{nf.format(value.denominator)}</strong>
          Eligible
        </span>
      </div>
      <div className="rd-heat-tooltip-hint">
        Click to inspect companies & users
      </div>
    </div>,
    document.body,
  );
}

function HeatCell({
  retained,
  denominator,
  label,
  period,
  index,
  onClick,
  onTooltip,
  onTooltipHide,
}: {
  retained: number | null;
  denominator: number;
  label: string;
  period: string;
  index: number;
  onClick?: () => void;
  onTooltip: (value: TooltipState) => void;
  onTooltipHide: () => void;
}) {
  if (retained == null || denominator === 0) {
    return (
      <td>
        <span
          className="heat-cell unavailable"
          aria-label="Not yet eligible"
        >
          -
        </span>
      </td>
    );
  }

  const percent = (100 * retained) / denominator;
  const show = (element: HTMLElement) =>
    onTooltip({
      rect: element.getBoundingClientRect(),
      label,
      period,
      index,
      retained,
      denominator,
    });

  return (
    <td>
      <button
        type="button"
        className="heat-cell"
        style={cellStyle(retained, denominator)}
        aria-label={`${label}, ${period.toLowerCase()} ${index}: ${retained} retained, ${denominator - retained} churned out of ${denominator}. View companies and users.`}
        onMouseEnter={event => show(event.currentTarget)}
        onMouseLeave={onTooltipHide}
        onFocus={event => show(event.currentTarget)}
        onBlur={onTooltipHide}
        onClick={onClick}
      >
        <span className="percentage">{percent.toFixed(1)}%</span>
        <span className="fraction">
          {retained}/{denominator}
        </span>
      </button>
    </td>
  );
}

function pooled(
  rows: RetentionHeatmapRow[],
  columns: number,
): Array<{ retained: number; eligible: number }> {
  return Array.from({ length: columns }, (_, index) =>
    rows.reduce(
      (acc, row) => {
        const value = row.values[index];
        if (value != null) {
          acc.retained += value;
          acc.eligible += row.cohort_size;
        }
        return acc;
      },
      { retained: 0, eligible: 0 },
    ),
  );
}

export default function RetentionHeatmap({
  weekly,
  monthly,
  loading,
  onCellClick,
}: {
  weekly: RetentionHeatmapResponse;
  monthly: RetentionHeatmapResponse;
  loading?: boolean;
  onCellClick: (target: RetentionHeatmapTarget) => void;
}) {
  const [interval, setInterval] =
    useState<RetentionHeatmapInterval>("weekly");
  const [order, setOrder] = useState<"oldest" | "newest">("oldest");
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

  const data = interval === "monthly" ? monthly : weekly;
  const rows = useMemo(() => {
    const source = [...data.rows];
    return order === "newest" ? source.reverse() : source;
  }, [data.rows, order]);

  const period = interval === "monthly" ? "Month" : "Week";
  const columns = data.columns;
  const aggregate = pooled(rows, columns);
  const companies = rows.reduce((sum, row) => sum + row.cohort_size, 0);
  const reportHeight = Math.min(
    600,
    Math.max(365, 232 + rows.length * 45),
  );

  const toggleSort = () =>
    setOrder(current => (current === "oldest" ? "newest" : "oldest"));

  return (
    <>
      <article
        className="report-card rd-retention-report"
        style={{ height: reportHeight }}
      >
        <header className="report-header rd-retention-report-head">
          <div>
            <h2>Retention</h2>
            <p className="report-subtitle">
              {interval === "weekly"
                ? "Activation cohorts · core activity in subsequent completed weeks"
                : "Activation cohorts · core activity in subsequent completed months"}
            </p>
          </div>
          <div className="report-actions rd-retention-controls">
            <CompactMenuSelect
              value={interval}
              options={INTERVAL_OPTIONS}
              onChange={value => {
                setTooltip(null);
                setInterval(value);
              }}
              ariaLabel="Retention interval"
              className="rd-retention-interval-select"
            />
            <button
              type="button"
              className="ui-control rd-retention-sort"
              onClick={toggleSort}
              aria-label={
                order === "oldest"
                  ? "Sorted oldest first. Switch to newest first."
                  : "Sorted newest first. Switch to oldest first."
              }
              title="Toggle cohort sort order"
            >
              <span aria-hidden="true">{order === "oldest" ? "↑" : "↓"}</span>
              {order === "oldest" ? "Oldest first" : "Newest first"}
            </button>
          </div>
        </header>

        <div className="report-toolbar rd-retention-summary">
          <span>
            <strong>{rows.length} {interval} cohorts</strong>
            {rows.length ? (
              <>
                {" "}
                <span aria-hidden="true">·</span> {nf.format(companies)} activated companies
              </>
            ) : null}
            {loading ? <em>Updating…</em> : null}
          </span>
        </div>

        <div
          className="heatmap-scroll"
          role="region"
          tabIndex={0}
          aria-label={`${interval === "weekly" ? "Weekly" : "Monthly"} retention cohorts`}
        >
          <table
            className={
              "heatmap-table " + (interval === "monthly" ? "is-monthly" : "")
            }
            aria-label={`${interval === "weekly" ? "Weekly" : "Monthly"} company retention`}
          >
            <thead>
              <tr>
                <th scope="col">Cohort {period.toLowerCase()}</th>
                <th scope="col" title="Companies in this activation cohort">
                  n
                </th>
                {Array.from({ length: columns }, (_, index) => (
                  <th scope="col" key={index}>
                    {period} {index + 1}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.length ? (
                rows.map(row => {
                  const label = cohortLabel(row.cohort_start, interval);
                  return (
                    <tr key={row.cohort_start}>
                      <th scope="row">{label}</th>
                      <td className="cohort-size">{row.cohort_size}</td>
                      {row.values.map((value, index) => (
                        <HeatCell
                          key={index}
                          retained={value}
                          denominator={row.cohort_size}
                          label={label}
                          period={period}
                          index={index + 1}
                          onTooltip={setTooltip}
                          onTooltipHide={() => setTooltip(null)}
                          onClick={
                            value == null
                              ? undefined
                              : () =>
                                  onCellClick({
                                    interval,
                                    cohortStart: row.cohort_start,
                                    relativePeriod: index + 1,
                                    retained: value,
                                    denominator: row.cohort_size,
                                    label,
                                    pooled: false,
                                  })
                          }
                        />
                      ))}
                    </tr>
                  );
                })
              ) : (
                <tr>
                  <td colSpan={columns + 2}>
                    <div className="heatmap-empty">
                      <strong>No {interval} activation cohorts in this range</strong>
                      <p>Choose a wider date range to see retention.</p>
                    </div>
                  </td>
                </tr>
              )}
            </tbody>
            {rows.length ? (
              <tfoot>
                <tr>
                  <th
                    scope="row"
                    title="Pooled retained companies divided by all eligible companies"
                  >
                    Average
                  </th>
                  <td className="cohort-size" />
                  {aggregate.map((cell, index) => (
                    <HeatCell
                      key={index}
                      retained={cell.eligible ? cell.retained : null}
                      denominator={cell.eligible}
                      label="All visible eligible cohorts"
                      period={period}
                      index={index + 1}
                      onTooltip={setTooltip}
                      onTooltipHide={() => setTooltip(null)}
                      onClick={
                        cell.eligible
                          ? () =>
                              onCellClick({
                                interval,
                                cohortStart: null,
                                relativePeriod: index + 1,
                                retained: cell.retained,
                                denominator: cell.eligible,
                                label: "All visible eligible cohorts",
                                pooled: true,
                              })
                          : undefined
                      }
                    />
                  ))}
                </tr>
              </tfoot>
            ) : null}
          </table>
        </div>

        <footer className="report-footer">
          <div className="heat-legend">
            <span>0%</span>
            <div className="legend-swatches" aria-hidden="true">
              <span style={{ background: "#eff4ff" }} />
              <span style={{ background: "#c5d3f7" }} />
              <span style={{ background: "#96acee" }} />
              <span style={{ background: "#6687e7" }} />
              <span style={{ background: "#1d4ed8" }} />
            </div>
            <span>100%</span>
          </div>
          <span className="legend-empty">
            <span aria-hidden="true" className="empty-swatch">-</span>
            Not yet eligible
          </span>
          {interval === "monthly" ? (
            <span className="window-key">Month 1 = next calendar month</span>
          ) : null}
        </footer>
      </article>

      <HeatmapTooltip value={tooltip} />
    </>
  );
}
