"use client";

import React, { useEffect, useMemo, useState } from "react";
import type { RetentionHeatmapTarget } from "./retention-heatmap";
import type {
  RetentionCellCompanyRow,
  RetentionCellDrillResponse,
  RetentionCellSegment,
} from "../../lib/retention/drill-types";

const nf = new Intl.NumberFormat("en-US");

function Icon({
  name,
}: {
  name: "left" | "right" | "down" | "close" | "search";
}) {
  const paths = {
    left: "m14 6-6 6 6 6",
    right: "m10 6 6 6-6 6",
    down: "m7 10 5 5 5-5",
    close: "m6 6 12 12M18 6 6 18",
    search: "M21 21l-4.35-4.35m1.35-5.65a7 7 0 1 1-14 0 7 7 0 0 1 14 0Z",
  };
  return (
    <svg className="rd-icon" viewBox="0 0 24 24" aria-hidden="true">
      <path d={paths[name]} />
    </svg>
  );
}

function prettyDate(value: string): string {
  return new Date(value.slice(0, 10) + "T12:00:00Z")
    .toLocaleDateString("en-GB", {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    })
    .replace("Sept", "Sep");
}

function periodLabel(target: RetentionHeatmapTarget): string {
  return `${target.interval === "weekly" ? "Week" : "Month"} ${target.relativePeriod}`;
}

function cacheKey(args: {
  target: RetentionHeatmapTarget;
  from: string | null;
  to: string | null;
  segment: RetentionCellSegment;
  query: string;
  page: number;
}) {
  return [
    args.target.interval,
    args.target.cohortStart ?? "all",
    String(args.target.relativePeriod),
    args.from ?? "all",
    args.to ?? "all",
    args.segment,
    args.query.trim().toLowerCase(),
    String(args.page),
  ].join("|");
}

const cache = new Map<string, RetentionCellDrillResponse>();

async function fetchCell(args: {
  target: RetentionHeatmapTarget;
  from: string | null;
  to: string | null;
  segment: RetentionCellSegment;
  query: string;
  page: number;
  signal?: AbortSignal;
}): Promise<RetentionCellDrillResponse> {
  const key = cacheKey(args);
  const cached = cache.get(key);
  if (cached) return cached;

  const response = await fetch("/api/retention-drill", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    signal: args.signal,
    body: JSON.stringify({
      action: "heatmap_cell",
      interval: args.target.interval,
      cohort_start: args.target.cohortStart,
      relative_period: args.target.relativePeriod,
      from: args.from,
      to: args.to,
      segment: args.segment,
      query: args.query,
      page: args.page,
      page_size: 8,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload?.error ?? "retention_cell_unavailable");
  }
  const result = payload as RetentionCellDrillResponse;
  cache.set(key, result);
  return result;
}

function prefetchCell(args: {
  target: RetentionHeatmapTarget;
  from: string | null;
  to: string | null;
  segment: RetentionCellSegment;
  query: string;
  page: number;
}) {
  const key = cacheKey(args);
  if (cache.has(key)) return;
  void fetchCell(args).catch(() => undefined);
}

function paginationItems(
  current: number,
  total: number,
): Array<number | "ellipsis"> {
  if (total <= 7) return Array.from({ length: total }, (_, index) => index + 1);
  if (current <= 4) return [1, 2, 3, 4, 5, "ellipsis", total];
  if (current >= total - 3)
    return [1, "ellipsis", total - 4, total - 3, total - 2, total - 1, total];
  return [1, "ellipsis", current - 1, current, current + 1, "ellipsis", total];
}

export default function RetentionCellModal({
  target,
  from,
  to,
  onClose,
  onCompany,
}: {
  target: RetentionHeatmapTarget;
  from: string | null;
  to: string | null;
  onClose: () => void;
  onCompany: (company: RetentionCellCompanyRow) => void;
}) {
  const [segment, setSegment] = useState<RetentionCellSegment>("all");
  const [query, setQuery] = useState("");
  const [deferredQuery, setDeferredQuery] = useState("");
  const [page, setPage] = useState(1);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [data, setData] = useState<RetentionCellDrillResponse | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const timer = setTimeout(() => setDeferredQuery(query), 250);
    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    setPage(1);
    setExpanded(new Set());
  }, [segment, deferredQuery, target]);

  useEffect(() => {
    const controller = new AbortController();
    const args = {
      target,
      from,
      to,
      segment,
      query: deferredQuery,
      page,
    };
    const cached = cache.get(cacheKey(args));
    if (cached) {
      setData(cached);
      setLoading(false);
      const pageCount = Math.max(1, Math.ceil(cached.total / cached.page_size));
      if (page > 1) prefetchCell({ ...args, page: page - 1 });
      if (page < pageCount) prefetchCell({ ...args, page: page + 1 });
      return () => controller.abort();
    }

    setLoading(true);
    fetchCell({ ...args, signal: controller.signal })
      .then(result => {
        if (controller.signal.aborted) return;
        setData(result);
        const pageCount = Math.max(1, Math.ceil(result.total / result.page_size));
        if (result.page > 1) prefetchCell({ ...args, page: result.page - 1 });
        if (result.page < pageCount)
          prefetchCell({ ...args, page: result.page + 1 });
      })
      .catch(() => {
        if (!controller.signal.aborted) setData(null);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [target, from, to, segment, deferredQuery, page]);

  const pageCount = Math.max(
    1,
    Math.ceil((data?.total ?? 0) / (data?.page_size ?? 8)),
  );
  const safePage = data?.page ?? page;
  const counts = data?.counts ?? {
    all: target.denominator,
    retained: target.retained,
    churned: target.denominator - target.retained,
  };

  const title = target.pooled
    ? `All visible cohorts · ${periodLabel(target)}`
    : `${target.label} cohort · ${periodLabel(target)}`;

  const toggle = (id: string) =>
    setExpanded(current =>
      current.has(id) ? new Set() : new Set([id]),
    );

  return (
    <div className="rd-overlay" role="presentation">
      <section
        className="rd-modal rd-activation-modal rd-retention-cell-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="retention-cell-title"
      >
        <header className="rd-modal-head">
          <div>
            <p>Retention cohort · {title}</p>
            <h2 id="retention-cell-title">
              {target.retained} / {target.denominator} retained ·{" "}
              {((100 * target.retained) / target.denominator).toFixed(1)}%
            </h2>
            <span>
              Company retention is based on non-failed core activity in the
              selected completed return window.
            </span>
          </div>
          <button
            type="button"
            className="rd-close"
            onClick={onClose}
            aria-label="Close retention cell drill"
          >
            <Icon name="close" />
          </button>
        </header>

        <div className="rd-drill-toolbar">
          <div className="rd-status-tabs" role="tablist" aria-label="Retention segment">
            {([
              ["all", "All", counts.all],
              ["retained", "Retained", counts.retained],
              ["churned", "Churned", counts.churned],
            ] as const).map(([key, label, count]) => (
              <button
                type="button"
                key={key}
                aria-pressed={segment === key}
                onClick={() => setSegment(key)}
              >
                {label}
                <span>{nf.format(count)}</span>
              </button>
            ))}
          </div>

          <div className="rd-search">
            <Icon name="search" />
            <input
              value={query}
              onChange={event => setQuery(event.currentTarget.value)}
              placeholder="Search companies or users"
              aria-label="Search companies or users"
            />
            {query ? (
              <button
                type="button"
                onClick={() => setQuery("")}
                aria-label="Clear search"
              >
                <Icon name="close" />
              </button>
            ) : null}
          </div>
        </div>

        <div className="rd-table-wrap">
          {loading && !data ? (
            <div className="rd-loading">Loading retained and churned companies…</div>
          ) : !data ? (
            <div className="rd-empty">Couldn’t load this retention cell.</div>
          ) : (
            <table className="rd-activation-table rd-retention-cell-table">
              <thead>
                <tr>
                  <th><span className="sr-only">Expand users</span></th>
                  <th>Company / user</th>
                  <th>Status</th>
                  <th>Users</th>
                  <th>Core</th>
                  <th>AP</th>
                  <th>AR</th>
                  <th>Transaction</th>
                  <th>Sync</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.length ? data.rows.flatMap(company => {
                  const open = expanded.has(company.id);
                  const parent = (
                    <tr key={company.id} className={open ? "is-expanded" : ""}>
                      <td>
                        <button
                          type="button"
                          className="rd-expander"
                          onClick={() => toggle(company.id)}
                          aria-label={(open ? "Collapse " : "Expand ") + company.name}
                        >
                          <Icon name={open ? "down" : "right"} />
                        </button>
                      </td>
                      <td>
                        <button
                          type="button"
                          className="rd-company-link"
                          onClick={() => onCompany(company)}
                        >
                          <strong>{company.name}</strong>
                          <span>
                            {company.integration}
                            {company.is_test ? " · Test" : ""}
                          </span>
                        </button>
                      </td>
                      <td>
                        <span
                          className={
                            "rd-status " +
                            (company.retained ? "activated" : "no_training")
                          }
                        >
                          {company.retained ? "Retained" : "Churned"}
                        </span>
                      </td>
                      <td>
                        {company.active_users}/{company.observed_users}
                      </td>
                      <td className={company.core_events ? "has-value" : ""}>
                        {nf.format(company.core_events)}
                      </td>
                      <td className={company.totals.ap ? "has-value" : ""}>
                        {nf.format(company.totals.ap)}
                      </td>
                      <td className={company.totals.ar ? "has-value" : ""}>
                        {nf.format(company.totals.ar)}
                      </td>
                      <td className={company.totals.transactions ? "has-value" : ""}>
                        {nf.format(company.totals.transactions)}
                      </td>
                      <td className={company.totals.sync ? "has-value" : ""}>
                        {nf.format(company.totals.sync)}
                      </td>
                    </tr>
                  );

                  if (!open) return [parent];

                  const visibleUsers = company.users.slice(0, 5);
                  const children = visibleUsers.map(user => (
                    <tr className="rd-user-row" key={company.id + "-" + user.id}>
                      <td />
                      <td>
                        <span className="rd-user-indent">{user.email}</span>
                      </td>
                      <td>
                        <span
                          className={
                            "rd-status " + (user.active ? "activated" : "")
                          }
                        >
                          {user.active ? "Active" : "No activity"}
                        </span>
                      </td>
                      <td />
                      <td>{nf.format(user.core_events)}</td>
                      <td>{nf.format(user.totals.ap)}</td>
                      <td>{nf.format(user.totals.ar)}</td>
                      <td>{nf.format(user.totals.transactions)}</td>
                      <td>{nf.format(user.totals.sync)}</td>
                    </tr>
                  ));

                  if (company.users.length > visibleUsers.length) {
                    children.push(
                      <tr
                        className="rd-user-row rd-more-users-row"
                        key={company.id + "-more"}
                      >
                        <td />
                        <td colSpan={8}>
                          <button
                            type="button"
                            onClick={() => onCompany(company)}
                          >
                            +{company.users.length - visibleUsers.length} more users
                            · View company profile
                          </button>
                        </td>
                      </tr>,
                    );
                  }

                  return [parent, ...children];
                }) : (
                  <tr>
                    <td colSpan={9}>
                      <div className="rd-empty">No matching companies.</div>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          )}
        </div>

        <footer className="rd-modal-foot rd-modal-foot-paginated">
          <div className="rd-table-summary">
            <span>
              User rows are active/inactive in this return window. Retention
              status remains a company-level metric.
            </span>
            <small>{data ? nf.format(data.total) + " matching companies" : ""}</small>
          </div>

          {data && data.total ? (
            <nav className="rd-pagination" aria-label="Retention drill pages">
              <button
                type="button"
                disabled={safePage === 1}
                onClick={() => setPage(value => Math.max(1, value - 1))}
                aria-label="Previous page"
              >
                <Icon name="left" />
              </button>
              {paginationItems(safePage, pageCount).map((item, index) =>
                item === "ellipsis" ? (
                  <span className="rd-page-ellipsis" key={"e-" + index}>…</span>
                ) : (
                  <button
                    type="button"
                    key={item}
                    aria-current={safePage === item ? "page" : undefined}
                    onClick={() => setPage(item)}
                  >
                    {item}
                  </button>
                ),
              )}
              <button
                type="button"
                disabled={safePage === pageCount}
                onClick={() => setPage(value => Math.min(pageCount, value + 1))}
                aria-label="Next page"
              >
                <Icon name="right" />
              </button>
            </nav>
          ) : null}
        </footer>
      </section>
    </div>
  );
}
