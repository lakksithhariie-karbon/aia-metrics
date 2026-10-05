"use client";

import React, { useEffect, useMemo, useState } from "react";
import type {
  RetentionHeatmapInterval,
  RetentionHeatmapResponse,
  RetentionHeatmapRow,
} from "../../lib/retention/types";

const nf = new Intl.NumberFormat("en-US");

async function loadHeatmap(
  interval: RetentionHeatmapInterval,
  from: string | null,
  to: string | null,
  signal?: AbortSignal,
): Promise<RetentionHeatmapResponse> {
  const response = await fetch("/api/retention-heatmap", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ interval, from, to }),
    signal,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      typeof payload?.error === "string"
        ? payload.error
        : "retention_heatmap_unavailable",
    );
  }
  return payload as RetentionHeatmapResponse;
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

function HeatCell({
  retained,
  denominator,
  label,
  period,
  index,
}: {
  retained: number | null;
  denominator: number;
  label: string;
  period: string;
  index: number;
}) {
  if (retained == null || denominator === 0) {
    return (
      <td>
        <span
          className="heat-cell unavailable"
          title="This return window is not yet eligible"
        >
          -
        </span>
      </td>
    );
  }

  const percent = (100 * retained) / denominator;
  return (
    <td>
      <span
        className="heat-cell"
        style={cellStyle(retained, denominator)}
        title={`${label} · ${period} ${index} · ${retained} retained · ${denominator - retained} churned · ${percent.toFixed(1)}% retention`}
      >
        <span className="percentage">{percent.toFixed(1)}%</span>
        <span className="fraction">
          {retained}/{denominator}
        </span>
      </span>
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
  from,
  to,
}: {
  from: string | null;
  to: string | null;
}) {
  const [interval, setInterval] =
    useState<RetentionHeatmapInterval>("weekly");
  const [order, setOrder] = useState<"oldest" | "newest">("oldest");
  const [data, setData] = useState<RetentionHeatmapResponse | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    loadHeatmap(interval, from, to, controller.signal)
      .then(setData)
      .catch(() => setData(null))
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [interval, from, to]);

  const rows = useMemo(() => {
    const source = [...(data?.rows ?? [])];
    return order === "newest" ? source.reverse() : source;
  }, [data, order]);

  const period = interval === "monthly" ? "Month" : "Week";
  const columns = data?.columns ?? (interval === "monthly" ? 6 : 8);
  const aggregate = pooled(rows, columns);
  const companies = rows.reduce((sum, row) => sum + row.cohort_size, 0);

  const reportHeight = Math.min(
    600,
    Math.max(365, 232 + rows.length * 45),
  );

  return (
    <article
      className="report-card rd-retention-report"
      style={{ height: reportHeight }}
    >
      <header className="report-header">
        <div>
          <h2>Retention</h2>
          <p className="report-subtitle">
            {interval === "weekly"
              ? "Activation cohorts · core activity in subsequent completed weeks"
              : "Activation cohorts · core activity in subsequent completed months"}
          </p>
        </div>
        <div className="report-actions">
          <select
            className="ui-control rd-retention-select"
            aria-label="Retention interval"
            value={interval}
            onChange={event =>
              setInterval(
                event.currentTarget.value as RetentionHeatmapInterval,
              )
            }
          >
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
          </select>
        </div>
      </header>

      <div className="report-toolbar">
        <span>
          <strong>
            {loading ? "Loading…" : `${rows.length} ${interval} cohorts`}
          </strong>
          {!loading && rows.length ? (
            <>
              {" "}
              <span aria-hidden="true">·</span> {nf.format(companies)} companies
            </>
          ) : null}
        </span>
        <select
          className="ui-control rd-retention-order"
          aria-label="Cohort order"
          value={order}
          onChange={event =>
            setOrder(event.currentTarget.value as "oldest" | "newest")
          }
        >
          <option value="oldest">Oldest first</option>
          <option value="newest">Newest first</option>
        </select>
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
            {loading ? (
              <tr>
                <td colSpan={columns + 2}>
                  <div className="heatmap-empty">Loading retention…</div>
                </td>
              </tr>
            ) : rows.length ? (
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
          {!loading && rows.length ? (
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
          <span aria-hidden="true" className="empty-swatch">
            -
          </span>
          Not yet eligible
        </span>
        {interval === "monthly" ? (
          <span className="window-key">Month 1 = next calendar month</span>
        ) : null}
      </footer>
    </article>
  );
}
