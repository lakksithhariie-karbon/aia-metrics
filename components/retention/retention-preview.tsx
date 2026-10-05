"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import type { RetentionKpiResponse } from "../../lib/retention/types";
import type {
  ActivationCompanyDetail,
  ActivationCompanyRow,
  ActivationListResponse,
  ActivationModuleTotals,
  ActivationStatus,
} from "../../lib/retention/drill-types";

type IconName =
  | "grid" | "trend" | "help" | "calendar" | "down" | "up"
  | "left" | "right" | "close" | "search" | "check" | "arrow"
  | "info" | "clock" | "users";

function Icon({ name }: { name: IconName }) {
  const paths: Partial<Record<IconName, string>> = {
    trend: "m3 17 6-6 4 4 8-10m-6 0h6v6",
    down: "m7 10 5 5 5-5",
    up: "m7 14 5-5 5 5",
    left: "m14 6-6 6 6 6",
    right: "m10 6 6 6-6 6",
    close: "m6 6 12 12M18 6 6 18",
    arrow: "M5 12h14m-5-5 5 5-5 5",
    check: "m5 12 4 4L19 6",
    clock: "M12 6v6l4 2",
    users: "M16 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2m6.5-10a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm7.5 4a4 4 0 0 1 4 4v2m-4-10a4 4 0 0 1 0 8",
  };
  return (
    <svg className="rd-icon" viewBox="0 0 24 24" aria-hidden="true">
      {name === "grid" ? (
        <>
          <rect x="3.5" y="3.5" width="6" height="6" rx="1" />
          <rect x="14.5" y="3.5" width="6" height="6" rx="1" />
          <rect x="3.5" y="14.5" width="6" height="6" rx="1" />
          <rect x="14.5" y="14.5" width="6" height="6" rx="1" />
        </>
      ) : name === "search" ? (
        <>
          <circle cx="10.5" cy="10.5" r="6.5" />
          <path d="m16 16 4.5 4.5" />
        </>
      ) : name === "calendar" ? (
        <>
          <rect x="4" y="5" width="16" height="16" rx="2" />
          <path d="M8 3v4m8-4v4M4 10h16" />
        </>
      ) : name === "help" || name === "info" ? (
        <>
          <circle cx="12" cy="12" r="9" />
          <path d={name === "help" ? "M9.5 8.7a2.6 2.6 0 0 1 5 1c0 1.8-2.5 2-2.5 3.8M12 16.8v.1" : "M12 10.5v6M12 7.3v.1"} />
        </>
      ) : name === "clock" ? (
        <>
          <circle cx="12" cy="12" r="9" />
          <path d={paths.clock} />
        </>
      ) : (
        <path d={paths[name]} />
      )}
    </svg>
  );
}

const nf = new Intl.NumberFormat("en-US");
const MONTH_NAMES = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

function istMonth(): string {
  return new Date().toLocaleDateString("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
  });
}

function shiftMonth(month: string, offset: number): string {
  const parts = month.split("-").map(Number);
  const date = new Date(Date.UTC(parts[0], parts[1] - 1 + offset, 1));
  return date.toISOString().slice(0, 7);
}

function lastCompleteMonth(): string {
  return shiftMonth(istMonth(), -1);
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

function lastDayOfMonth(month: string): string {
  const next = shiftMonth(month, 1);
  const ms = Date.parse(next + "-01T00:00:00Z") - 86_400_000;
  return new Date(ms).toISOString().slice(0, 10);
}

function rangeLabel(range: MonthRange): string {
  if (range.preset === "lifetime") return "Lifetime";
  if (range.start === range.end) return monthLabel(range.start);
  return monthLabel(range.start) + " – " + monthLabel(range.end);
}

function bounds(range: MonthRange) {
  if (range.preset === "lifetime") return { from: null, to: null };
  return {
    from: range.start + "-01",
    to: lastDayOfMonth(range.end),
  };
}

function prettyDate(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "Asia/Kolkata",
  }).replace("Sept", "Sep");
}

function prettyDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString("en-IN", {
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "Asia/Kolkata",
  }).replace("Sept", "Sep");
}

function ttvLabel(hours: number | null): string {
  if (hours == null || !Number.isFinite(hours)) return "—";
  if (hours < 24) return Math.round(hours) + "h";
  return (hours / 24).toFixed(1) + "d";
}

function cardTtv(hours: number | null): { value: string; unit: string } {
  if (hours == null || !Number.isFinite(hours)) return { value: "—", unit: "" };
  return { value: (hours / 24).toFixed(1), unit: "days" };
}

function statusLabel(status: ActivationStatus): string {
  if (status === "activated") return "Activated";
  if (status === "awaiting_sync") return "Awaiting sync";
  if (status === "no_core") return "No core work";
  return "No training sync";
}

function moduleTotal(totals: ActivationModuleTotals): number {
  return totals.ap + totals.ar + totals.transactions + totals.gst;
}

interface MonthRange {
  preset: "lifetime" | "last" | "3" | "6" | "12" | "custom";
  start: string;
  end: string;
}

function defaultRange(): MonthRange {
  const month = lastCompleteMonth();
  return { preset: "last", start: month, end: month };
}

function presetRange(preset: MonthRange["preset"]): MonthRange {
  const end = lastCompleteMonth();
  if (preset === "lifetime") return { preset, start: end, end };
  if (preset === "last") return { preset, start: end, end };
  if (preset === "custom") return { preset, start: end, end };
  const count = Number(preset);
  return { preset, start: shiftMonth(end, 1 - count), end };
}

async function post<T>(url: string, body: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload?.error || "request_failed");
  return payload as T;
}

const activationPageCache = new Map<string, ActivationListResponse>();
const companyDetailCache = new Map<string, ActivationCompanyDetail>();
const companyDetailPromises = new Map<string, Promise<ActivationCompanyDetail>>();

function activationPageKey(args: {
  from: string | null;
  to: string | null;
  query: string;
  status: ActivationStatus | "all";
  page: number;
}): string {
  return [
    args.from ?? "all",
    args.to ?? "all",
    args.status,
    args.query.trim().toLowerCase(),
    String(args.page),
  ].join("|");
}

async function fetchActivationPage(
  args: {
    from: string | null;
    to: string | null;
    query: string;
    status: ActivationStatus | "all";
    page: number;
  },
  signal?: AbortSignal,
): Promise<ActivationListResponse> {
  const key = activationPageKey(args);
  const cached = activationPageCache.get(key);
  if (cached) return cached;

  const result = await post<ActivationListResponse>(
    "/api/retention-drill-preview",
    {
      action: "list",
      from: args.from,
      to: args.to,
      query: args.query,
      status: args.status,
      page: args.page,
      page_size: 8,
    },
    signal,
  );
  activationPageCache.set(key, result);
  return result;
}

function prefetchActivationPage(args: {
  from: string | null;
  to: string | null;
  query: string;
  status: ActivationStatus | "all";
  page: number;
}) {
  const key = activationPageKey(args);
  if (activationPageCache.has(key)) return;
  void fetchActivationPage(args).catch(() => undefined);
}

function getCompanyDetail(companyId: string): Promise<ActivationCompanyDetail> {
  const cached = companyDetailCache.get(companyId);
  if (cached) return Promise.resolve(cached);
  const pending = companyDetailPromises.get(companyId);
  if (pending) return pending;

  const promise = post<ActivationCompanyDetail>(
    "/api/retention-drill-preview",
    { action: "company", company_id: companyId },
  )
    .then(result => {
      companyDetailCache.set(companyId, result);
      return result;
    })
    .finally(() => {
      companyDetailPromises.delete(companyId);
    });

  companyDetailPromises.set(companyId, promise);
  return promise;
}

function prefetchCompanyDetail(companyId: string) {
  void getCompanyDetail(companyId).catch(() => undefined);
}

function paginationItems(current: number, total: number): Array<number | "ellipsis"> {
  if (total <= 7) return Array.from({ length: total }, (_, index) => index + 1);
  if (current <= 4) return [1, 2, 3, 4, 5, "ellipsis", total];
  if (current >= total - 3)
    return [1, "ellipsis", total - 4, total - 3, total - 2, total - 1, total];
  return [1, "ellipsis", current - 1, current, current + 1, "ellipsis", total];
}

function KpiCard({
  label,
  period,
  value,
  unit,
  note,
  interactive,
  onClick,
}: {
  label: string;
  period: string;
  value: string;
  unit?: string;
  note: string;
  interactive?: boolean;
  onClick?: () => void;
}) {
  return (
    <article className={"rd-kpi-card " + (interactive ? "is-interactive" : "")}>
      {interactive ? (
        <button
          type="button"
          className="rd-card-hit-target"
          onClick={onClick}
          aria-label={label + ", " + value + ". View activation drill."}
        />
      ) : null}
      <div className="rd-card-top">
        <span>{label}</span>
        <span className="rd-card-period">{period}</span>
      </div>
      <div className="rd-card-value">
        {value}
        {unit ? <span>{unit}</span> : null}
      </div>
      <div className="rd-card-note">{note}</div>
    </article>
  );
}

function DatePicker({
  range,
  onApply,
}: {
  range: MonthRange;
  onApply: (value: MonthRange) => void;
}) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(range);
  const [year, setYear] = useState(Number(range.end.slice(0, 4)));
  const [awaitingEnd, setAwaitingEnd] = useState(false);
  const current = istMonth();
  const last = lastCompleteMonth();

  useEffect(() => setDraft(range), [range]);

  const chooseMonth = (key: string) => {
    if (key > current) return;
    if (!awaitingEnd) {
      setDraft({ preset: "custom", start: key, end: key });
      setAwaitingEnd(true);
    } else {
      const start = draft.start <= key ? draft.start : key;
      const end = draft.start <= key ? key : draft.start;
      setDraft({ preset: "custom", start, end });
      setAwaitingEnd(false);
    }
  };

  return (
    <div className="rd-date-wrap">
      {range.preset !== "last" ? (
        <button
          type="button"
          className="rd-reset"
          onClick={() => onApply(defaultRange())}
        >
          Reset
        </button>
      ) : null}
      <span className="rd-date-label">Date range</span>
      <button
        type="button"
        className="rd-date-trigger"
        aria-expanded={open}
        onClick={() => {
          setDraft(range);
          setYear(Number(range.end.slice(0, 4)));
          setAwaitingEnd(false);
          setOpen(value => !value);
        }}
      >
        <Icon name="calendar" />
        <span>{rangeLabel(range)}</span>
        <Icon name="down" />
      </button>

      {open ? (
        <div className="rd-date-popover">
          <div className="rd-date-head">
            <div>
              <strong>Date range</strong>
              <span>Applies to the preview cards and activation cohort</span>
            </div>
            <button type="button" onClick={() => setOpen(false)} aria-label="Close date picker">
              <Icon name="close" />
            </button>
          </div>
          <div className="rd-date-body">
            <div className="rd-presets">
              {([
                ["last", "Last complete month"],
                ["3", "Last 3 months"],
                ["6", "Last 6 months"],
                ["12", "Last 12 months"],
                ["lifetime", "Lifetime"],
                ["custom", "Custom range"],
              ] as const).map(([preset, label]) => {
                const next = preset === "custom" ? draft : presetRange(preset);
                return (
                  <button
                    type="button"
                    key={preset}
                    aria-pressed={draft.preset === preset}
                    onClick={() => {
                      setDraft(next);
                      setAwaitingEnd(false);
                    }}
                  >
                    <span>
                      <strong>{label}</strong>
                      <small>{preset === "lifetime" ? "All available integrations" : rangeLabel(next)}</small>
                    </span>
                    <Icon name="check" />
                  </button>
                );
              })}
            </div>
            <div className="rd-month-picker">
              <div className="rd-range-fields">
                <div>
                  <span>Start</span>
                  <strong>{draft.preset === "lifetime" ? "All time" : monthLabel(draft.start)}</strong>
                </div>
                <Icon name="arrow" />
                <div>
                  <span>End</span>
                  <strong>{draft.preset === "lifetime" ? "Present" : monthLabel(draft.end)}</strong>
                </div>
              </div>
              <div className="rd-month-head">
                <strong>{year}</strong>
                <div>
                  <button type="button" onClick={() => setYear(value => value - 1)} aria-label="Previous year">
                    <Icon name="left" />
                  </button>
                  <button
                    type="button"
                    onClick={() => setYear(value => value + 1)}
                    disabled={year >= Number(current.slice(0, 4))}
                    aria-label="Next year"
                  >
                    <Icon name="right" />
                  </button>
                </div>
              </div>
              <div className="rd-month-grid">
                {MONTH_NAMES.map((name, index) => {
                  const key = year + "-" + String(index + 1).padStart(2, "0");
                  const selected =
                    draft.preset !== "lifetime" &&
                    key >= draft.start &&
                    key <= draft.end;
                  return (
                    <button
                      type="button"
                      key={key}
                      disabled={key > current}
                      className={
                        (selected ? "in-range " : "") +
                        (key === draft.start || key === draft.end ? "endpoint " : "") +
                        (key === last ? "last-complete" : "")
                      }
                      onClick={() => chooseMonth(key)}
                    >
                      {name}
                    </button>
                  );
                })}
              </div>
              <p>{awaitingEnd ? "Choose an end month, or apply to keep one month." : "Choose one month, then another to extend the range."}</p>
            </div>
          </div>
          <div className="rd-date-foot">
            <span>{rangeLabel(draft)}</span>
            <div>
              <button type="button" onClick={() => setOpen(false)}>Cancel</button>
              <button
                type="button"
                className="primary"
                onClick={() => {
                  onApply(draft);
                  setOpen(false);
                }}
              >
                Apply
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function ActivationModal({
  range,
  kpis,
  onClose,
}: {
  range: MonthRange;
  kpis: RetentionKpiResponse;
  onClose: () => void;
}) {
  const [data, setData] = useState<ActivationListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState("");
  const [deferredQuery, setDeferredQuery] = useState("");
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [status, setStatus] = useState<ActivationStatus | "all">("all");
  const [detailId, setDetailId] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const rangeBounds = useMemo(() => bounds(range), [range]);

  useEffect(() => {
    const timer = setTimeout(() => setDeferredQuery(query), 250);
    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    setPage(1);
    setExpanded(new Set());
  }, [status, deferredQuery, rangeBounds.from, rangeBounds.to]);

  useEffect(() => {
    const controller = new AbortController();
    const args = {
      from: rangeBounds.from,
      to: rangeBounds.to,
      query: deferredQuery,
      status,
      page,
    };
    const cached = activationPageCache.get(activationPageKey(args));
    if (cached) {
      setData(cached);
      setLoading(false);
      const totalPages = Math.max(1, Math.ceil(cached.total / cached.page_size));
      if (page > 1) prefetchActivationPage({ ...args, page: page - 1 });
      if (page < totalPages) prefetchActivationPage({ ...args, page: page + 1 });
      return () => controller.abort();
    }

    setLoading(true);
    fetchActivationPage(args, controller.signal)
      .then(result => {
        if (controller.signal.aborted) return;
        setData(result);
        const totalPages = Math.max(1, Math.ceil(result.total / result.page_size));
        if (result.page > 1)
          prefetchActivationPage({ ...args, page: result.page - 1 });
        if (result.page < totalPages)
          prefetchActivationPage({ ...args, page: result.page + 1 });
      })
      .catch(() => {
        if (!controller.signal.aborted) setData(null);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [rangeBounds.from, rangeBounds.to, deferredQuery, status, page]);

  const counts = {
    all: kpis.activation.integrated,
    activated: kpis.activation.activated,
    no_training: kpis.activation.integrated - kpis.activation.trained,
    no_core: kpis.activation.trained - kpis.activation.post_training_core,
    awaiting_sync: kpis.activation.post_training_core - kpis.activation.activated,
  };

  const visible = data?.rows ?? [];
  const pageCount = Math.max(
    1,
    Math.ceil((data?.total ?? 0) / (data?.page_size ?? 8)),
  );
  const safePage = data?.page ?? page;
  const pagedVisible = visible;

  const toggle = (id: string) => {
    setExpanded(current =>
      current.has(id) ? new Set() : new Set([id]),
    );
  };

  return (
    <>
      <div className="rd-overlay" role="presentation">
        <section className="rd-modal rd-activation-modal" role="dialog" aria-modal="true" aria-labelledby="activation-preview-title">
          <header className="rd-modal-head">
            <div>
              <p>Activation cohort · {rangeLabel(range)}</p>
              <h2 id="activation-preview-title">Activation rate</h2>
              <span>{nf.format(kpis.activation.activated)} of {nf.format(kpis.activation.integrated)} integrated companies activated</span>
            </div>
            <button type="button" className="rd-close" onClick={onClose} aria-label="Close activation drill">
              <Icon name="close" />
            </button>
          </header>

          <div className="rd-funnel">
            <div>
              <span>Integrated</span>
              <strong>{nf.format(kpis.activation.integrated)}</strong>
              <small>Successful integration</small>
            </div>
            <i>→</i>
            <div>
              <span>Training sync</span>
              <strong>{nf.format(kpis.activation.trained)}</strong>
              <small>{nf.format(counts.no_training)} dropped</small>
            </div>
            <i>→</i>
            <div>
              <span>Independent core work</span>
              <strong>{nf.format(kpis.activation.post_training_core)}</strong>
              <small>{nf.format(counts.no_core)} dropped</small>
            </div>
            <i>→</i>
            <div className="is-final">
              <span>Activated</span>
              <strong>{nf.format(kpis.activation.activated)}</strong>
              <small>{nf.format(counts.awaiting_sync)} awaiting sync</small>
            </div>
          </div>

          <div className="rd-drill-toolbar">
            <div className="rd-status-tabs" role="tablist" aria-label="Activation status">
              {([
                ["all", "All"],
                ["activated", "Activated"],
                ["no_training", "No training"],
                ["no_core", "No core work"],
                ["awaiting_sync", "Awaiting sync"],
              ] as const).map(([key, label]) => (
                <button
                  type="button"
                  key={key}
                  aria-pressed={status === key}
                  onClick={() => setStatus(key)}
                >
                  {label}
                  <span>{nf.format(counts[key])}</span>
                </button>
              ))}
            </div>
            <div className="rd-search">
              <Icon name="search" />
              <input
                value={query}
                onChange={event => setQuery(event.currentTarget.value)}
                placeholder="Search companies"
                aria-label="Search companies"
              />
              {query ? (
                <button type="button" onClick={() => setQuery("")} aria-label="Clear search">
                  <Icon name="close" />
                </button>
              ) : null}
            </div>
          </div>

          <div className="rd-table-wrap">
            {loading ? (
              <div className="rd-loading">Loading live company activity…</div>
            ) : !data ? (
              <div className="rd-empty">Couldn’t load the activation drill.</div>
            ) : (
              <table className="rd-activation-table">
                <thead>
                  <tr>
                    <th><span className="sr-only">Expand</span></th>
                    <th>Company</th>
                    <th>Status</th>
                    <th>Integration</th>
                    <th>TTV</th>
                    <th>AP</th>
                    <th>AR</th>
                    <th>Transaction</th>
                    <th>GST</th>
                  </tr>
                </thead>
                <tbody>
                  {pagedVisible.length ? pagedVisible.flatMap(company => {
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
                            onMouseEnter={() => prefetchCompanyDetail(company.id)}
                            onFocus={() => prefetchCompanyDetail(company.id)}
                            onClick={() => setDetailId(company.id)}
                          >
                            <strong>{company.name}</strong>
                            <span>{company.integration}{company.is_test ? " · Test" : ""}</span>
                          </button>
                        </td>
                        <td><span className={"rd-status " + company.status}>{statusLabel(company.status)}</span></td>
                        <td>{prettyDate(company.integration_at)}</td>
                        <td>{ttvLabel(company.ttv_hours)}</td>
                        <td className={company.totals.ap ? "has-value" : ""}>{nf.format(company.totals.ap)}</td>
                        <td className={company.totals.ar ? "has-value" : ""}>{nf.format(company.totals.ar)}</td>
                        <td className={company.totals.transactions ? "has-value" : ""}>{nf.format(company.totals.transactions)}</td>
                        <td className={company.totals.gst ? "has-value" : ""}>{nf.format(company.totals.gst)}</td>
                      </tr>
                    );
                    if (!open) return [parent];
                    const visibleUsers = company.users.slice(0, 5);
                    const children = company.users.length
                      ? visibleUsers.map(user => (
                          <tr className="rd-user-row" key={company.id + "-" + user.id}>
                            <td />
                            <td><span className="rd-user-indent">{user.email}</span></td>
                            <td />
                            <td />
                            <td />
                            <td>{nf.format(user.totals.ap)}</td>
                            <td>{nf.format(user.totals.ar)}</td>
                            <td>{nf.format(user.totals.transactions)}</td>
                            <td>{nf.format(user.totals.gst)}</td>
                          </tr>
                        ))
                      : [];
                    if (company.users.length > visibleUsers.length) {
                      children.push(
                        <tr className="rd-user-row rd-more-users-row" key={company.id + "-more-users"}>
                          <td />
                          <td colSpan={8}>
                            <button
                              type="button"
                              onMouseEnter={() => prefetchCompanyDetail(company.id)}
                              onFocus={() => prefetchCompanyDetail(company.id)}
                              onClick={() => setDetailId(company.id)}
                            >
                              +{company.users.length - visibleUsers.length} more users · View company profile
                            </button>
                          </td>
                        </tr>,
                      );
                    }
                    return [parent, ...children];
                  }) : (
                    <tr><td colSpan={9}><div className="rd-empty">No companies in this preview segment.</div></td></tr>
                  )}
                </tbody>
              </table>
            )}
          </div>

          <footer className="rd-modal-foot rd-modal-foot-paginated">
            <div className="rd-table-summary">
              <span>
                Independent usage is counted after the training day through activation, or through data freshness if not activated.
              </span>
              <small>
                {data
                  ? nf.format(data.total) + " matching companies"
                  : ""}
              </small>
            </div>
            {data && visible.length ? (
              <nav className="rd-pagination" aria-label="Activation company pages">
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
                    <span className="rd-page-ellipsis" key={"ellipsis-" + index}>…</span>
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

      {detailId ? (
        <CompanyDetailModal
          companyId={detailId}
          onClose={() => setDetailId(null)}
        />
      ) : null}
    </>
  );
}

function CompanyDetailModal({
  companyId,
  onClose,
}: {
  companyId: string;
  onClose: () => void;
}) {
  const initialDetail = companyDetailCache.get(companyId) ?? null;
  const [detail, setDetail] = useState<ActivationCompanyDetail | null>(initialDetail);
  const [loading, setLoading] = useState(!initialDetail);

  useEffect(() => {
    let active = true;
    const cached = companyDetailCache.get(companyId);
    if (cached) {
      setDetail(cached);
      setLoading(false);
      return () => {
        active = false;
      };
    }

    setLoading(true);
    getCompanyDetail(companyId)
      .then(result => {
        if (active) setDetail(result);
      })
      .catch(() => {
        if (active) setDetail(null);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [companyId]);

  return (
    <div className="rd-overlay rd-overlay-level-2" role="presentation">
      <section className="rd-modal rd-company-modal" role="dialog" aria-modal="true" aria-labelledby="company-preview-title">
        {loading ? (
          <div className="rd-loading rd-detail-loading">Loading company profile…</div>
        ) : !detail ? (
          <div className="rd-empty rd-detail-loading">
            Company details are unavailable.
            <button type="button" onClick={onClose}>Back</button>
          </div>
        ) : (
          <>
            <header className="rd-company-head">
              <div className="rd-company-topline">
                <button type="button" className="rd-back" onClick={onClose}>
                  <Icon name="left" />
                  Activation cohort
                </button>
                <button type="button" className="rd-close" onClick={onClose} aria-label="Close company detail">
                  <Icon name="close" />
                </button>
              </div>
              <div>
                <div>
                  <p>Company activation profile</p>
                  <h2 id="company-preview-title">{detail.name}</h2>
                </div>
                <div className="rd-company-tags">
                  <span>{detail.integration}</span>
                  {detail.is_test ? <span>Test</span> : null}
                  <span>{detail.observed_users} observed {detail.observed_users === 1 ? "user" : "users"}</span>
                </div>
              </div>
            </header>

            <div className="rd-company-scroll">
              <section className="rd-lifecycle-card">
                <div className="rd-section-title">
                  <div>
                    <h3>Activation journey</h3>
                    <p>Auditable milestones behind the activation decision</p>
                  </div>
                  <div className="rd-ttv-pill">
                    <span>Time to value</span>
                    <strong>{ttvLabel(detail.ttv_hours)}</strong>
                  </div>
                </div>
                <div className="rd-timeline">
                  {[
                    [detail.signup_kind === "Company Created" ? "Signed up" : "First seen", detail.signup_at],
                    ["Integrated", detail.integration_at],
                    ["Training sync", detail.training_sync_at],
                    ["Independent core work", detail.post_training_core_at],
                    ["Activated", detail.activated_at],
                  ].map(([label, value], index) => (
                    <div className={"rd-milestone " + (!value ? "is-empty" : "")} key={label}>
                      <span className="rd-dot" />
                      {index < 4 ? <i /> : null}
                      <small>{label}</small>
                      <strong>{prettyDateTime(value)}</strong>
                    </div>
                  ))}
                </div>
              </section>

              <section className="rd-health-strip">
                <div>
                  <span>Last core activity</span>
                  <strong>{prettyDate(detail.last_core_activity_at)}</strong>
                </div>
                <div>
                  <span>Active weeks</span>
                  <strong>{detail.active_weeks_8} / 8</strong>
                </div>
                <div>
                  <span>Observed users</span>
                  <strong>{detail.observed_users}</strong>
                </div>
                <div>
                  <span>Module events · 8w</span>
                  <strong>{nf.format(detail.module_events_8)}</strong>
                </div>
              </section>

              <section className="rd-detail-grid">
                <article className="rd-detail-card">
                  <div className="rd-section-title">
                    <div>
                      <h3>Activation evidence</h3>
                      <p>Independent work between training and the closing sync</p>
                    </div>
                  </div>
                  <div className="rd-evidence-list">
                    {detail.evidence.length ? detail.evidence.map((row, index) => (
                      <div key={row.at + "-" + index}>
                        <span className={"rd-module-pill module-" + row.module.toLowerCase().replace("transaction","txn")}>{row.module}</span>
                        <div>
                          <strong>{row.event}</strong>
                          <small>{row.user || "Unattributed"} · {prettyDateTime(row.at)}</small>
                        </div>
                      </div>
                    )) : <div className="rd-empty small">No independent activation evidence yet.</div>}
                  </div>
                </article>

                <article className="rd-detail-card">
                  <div className="rd-section-title">
                    <div>
                      <h3>Users</h3>
                      <p>Observed after integration · recent usage is last 8 completed weeks</p>
                    </div>
                  </div>
                  <div className="rd-users-list">
                    {detail.users.slice(0, 8).map(user => (
                      <div key={user.id}>
                        <div className="rd-user-copy">
                          <strong>{user.email}</strong>
                          <span>{prettyDate(user.first_seen_at)} → {prettyDate(user.last_seen_at)}</span>
                          {user.activation_role ? (
                            <small>
                              {user.activation_role === "both"
                                ? "Core job + closing sync"
                                : user.activation_role === "core_job"
                                  ? "Independent core job"
                                  : "Activation-closing sync"}
                            </small>
                          ) : null}
                        </div>
                        <div className="rd-user-usage">
                          <span>AP <b>{user.recent_totals.ap}</b></span>
                          <span>AR <b>{user.recent_totals.ar}</b></span>
                          <span>Txn <b>{user.recent_totals.transactions}</b></span>
                          <span>GST <b>{user.recent_totals.gst}</b></span>
                          <span>Sync <b>{user.recent_totals.sync}</b></span>
                        </div>
                      </div>
                    ))}
                  </div>
                </article>
              </section>

              <section className="rd-weeks-card">
                <div className="rd-section-title">
                  <div>
                    <h3>Recent usage</h3>
                    <p>Last 8 completed IST weeks · same AP / AR / Transaction / GST mapping as Companies</p>
                  </div>
                </div>
                <div className="rd-weeks-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Week</th>
                        <th>AP</th>
                        <th>AR</th>
                        <th>Transaction</th>
                        <th>GST</th>
                        <th>Sync</th>
                      </tr>
                    </thead>
                    <tbody>
                      {detail.weeks.map(week => (
                        <tr key={week.week_start}>
                          <td>
                            <strong>{prettyDate(week.week_start + "T12:00:00Z")}</strong>
                            <span>to {prettyDate(week.week_end + "T12:00:00Z")}</span>
                          </td>
                          <td>{nf.format(week.totals.ap)}</td>
                          <td>{nf.format(week.totals.ar)}</td>
                          <td>{nf.format(week.totals.transactions)}</td>
                          <td>{nf.format(week.totals.gst)}</td>
                          <td>{nf.format(week.totals.sync)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
            </div>
          </>
        )}
      </section>
    </div>
  );
}

export default function RetentionPreview() {
  const [range, setRange] = useState<MonthRange>(() => defaultRange());
  const [kpis, setKpis] = useState<RetentionKpiResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [activationOpen, setActivationOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const rangeBounds = useMemo(() => bounds(range), [range]);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    post<RetentionKpiResponse>(
      "/api/retention-kpis",
      rangeBounds,
      controller.signal,
    )
      .then(setKpis)
      .catch(() => setKpis(null))
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [rangeBounds.from, rangeBounds.to]);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (event.key === "Escape" && activationOpen) setActivationOpen(false);
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [activationOpen]);

  const ttv = cardTtv(kpis?.ttv.avg_hours ?? null);
  const activationRate = kpis?.activation.rate_pct == null
    ? "—"
    : Number(kpis.activation.rate_pct).toFixed(1) + "%";
  const churnRate = kpis?.churn.rate_pct == null
    ? "—"
    : Number(kpis.churn.rate_pct).toFixed(1) + "%";

  return (
    <div className="rd-shell">
      <header className="rd-header">
        <div className="rd-brand-left">
          <div className="rd-brand">
            <span><Icon name="grid" /></span>
            AI Accountant
          </div>
          <i />
          <span>Product Metrics</span>
        </div>
        <div className="rd-header-actions">
          <div className="rd-switcher">
            <button type="button" onClick={() => setMenuOpen(value => !value)} aria-expanded={menuOpen}>
              <Icon name="trend" />
              Retention & Churn
              <Icon name="down" />
            </button>
            {menuOpen ? (
              <div className="rd-switcher-menu">
                <a href="/overview">Product Overview<small>Active usage, adoption and workflow health</small></a>
                <a href="/retention-preview" className="current">Retention & Churn<small>Activation, retention and monthly churn</small></a>
                <a href="/customer">Companies<small>Module usage by company and user</small></a>
              </div>
            ) : null}
          </div>
          <button type="button" className="rd-help" aria-label="Preview information"><Icon name="help" /></button>
        </div>
      </header>

      <main className="rd-page">
        <div className="rd-page-head">
          <div>
            <h1>Retention & Churn</h1>
            <p>Activation quality, time to value, and completed-month churn</p>
          </div>
          <DatePicker range={range} onApply={setRange} />
        </div>

        <section className="rd-kpi-grid" aria-label="Retention key metrics">
          <KpiCard
            label="Activation rate"
            period={rangeLabel(range)}
            value={loading ? "…" : activationRate}
            note={
              kpis
                ? nf.format(kpis.activation.activated) + " of " + nf.format(kpis.activation.integrated) + " integrated companies activated"
                : "Live KPI unavailable"
            }
            interactive={Boolean(kpis)}
            onClick={() => setActivationOpen(true)}
          />
          <KpiCard
            label="Average time to value"
            period={rangeLabel(range)}
            value={loading ? "…" : ttv.value}
            unit={ttv.unit}
            note={
              kpis
                ? nf.format(kpis.ttv.companies) + " activated companies with measurable TTV"
                : "Live KPI unavailable"
            }
          />
          <KpiCard
            label="Monthly churn"
            period={kpis?.churn.month ? monthLabel(kpis.churn.month) : rangeLabel(range)}
            value={loading ? "…" : churnRate}
            note={
              kpis?.churn.month
                ? nf.format(kpis.churn.churned) + " of " + nf.format(kpis.churn.eligible) + " eligible companies churned"
                : "No completed churn month in this range"
            }
          />
        </section>

        <section className="rd-preview-placeholder">
          <div>
            <span>PREVIEW SCOPE</span>
            <h2>Cards + activation drill only</h2>
            <p>
              The retention heatmap and churn report are intentionally left out of this design spike.
              This lets us judge the card language, activation cohort table, and company-level drill before changing the rest of the page.
            </p>
          </div>
          <button
            type="button"
            disabled={!kpis}
            onClick={() => setActivationOpen(true)}
          >
            Explore activation drill
            <Icon name="right" />
          </button>
        </section>
      </main>

      {activationOpen && kpis ? (
        <ActivationModal
          range={range}
          kpis={kpis}
          onClose={() => setActivationOpen(false)}
        />
      ) : null}
    </div>
  );
}
