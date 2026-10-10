"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import ProductMetricsHeader from "../product-metrics-header";
import MetricsInfoDialog, {
  MetricsInfoButton,
  metricsInfoDefinitions,
} from "../ui/metrics-info";
import {
  MONTH_MODULES,
  type CalendarMonthUsage,
  type CompanyUsageResponse,
  type CompanyUsageRow,
  type CompanyUsageUser,
  type ModuleBreakdownResponse,
  type MonthModuleKey,
  type SortDirection,
  type SortKey,
  type UsageFilter,
} from "../../lib/companies/types";

type IconName =
  | "grid" | "trend" | "help" | "calendar" | "down" | "up" | "left"
  | "right" | "arrow" | "close" | "search" | "filter" | "plus"
  | "minus" | "sort" | "check" | "info";

function Icon({ name }: { name: IconName }) {
  const paths: Partial<Record<IconName, string>> = {
    trend: "m3 17 6-6 4 4 8-10m-6 0h6v6",
    down: "m7 10 5 5 5-5",
    up: "m7 14 5-5 5 5",
    left: "m14 6-6 6 6 6",
    right: "m10 6 6 6-6 6",
    arrow: "M5 12h14m-5-5 5 5-5 5",
    close: "m6 6 12 12M18 6 6 18",
    filter: "M3 4h18l-7 8v7l-4 2v-9z",
    plus: "M5 12h14M12 5v14",
    minus: "M5 12h14",
    sort: "M8 4v16m-3-3 3 3 3-3M16 20V4m-3 3 3-3 3 3",
    check: "m5 12 4 4L19 6",
  };
  return (
    <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
      {name === "grid"
        ? [[3.5, 3.5], [14.5, 3.5], [3.5, 14.5], [14.5, 14.5]].map(([x, y]) => (
            <rect key={`${x}-${y}`} x={x} y={y} width="6" height="6" rx="1" />
          ))
        : name === "search"
          ? [<circle key="c" cx="10.5" cy="10.5" r="6.5" />, <path key="p" d="m16 16 4.5 4.5" />]
          : name === "calendar"
            ? [<rect key="r" x="4" y="5" width="16" height="16" rx="2" />, <path key="p" d="M8 3v4m8-4v4M4 10h16m-12 4h2m4 0h2" />]
            : name === "help" || name === "info"
              ? [<circle key="c" cx="12" cy="12" r="9" />, <path key="p" d={name === "help" ? "M9.5 8.7a2.6 2.6 0 0 1 5 1c0 1.8-2.5 2-2.5 3.8M12 16.8v.1" : "M12 10.5v6M12 7.3v.1"} />]
              : <path d={paths[name]} />}
    </svg>
  );
}

const number = new Intl.NumberFormat("en-US");
const DATA_START_MONTH = "2026-03";

function currentMonthIST(): string {
  return new Date()
    .toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" })
    .slice(0, 7);
}
function shiftMonth(month: string, offset: number): string {
  const [year, value] = month.split("-").map(Number);
  return new Date(Date.UTC(year, value - 1 + offset, 1))
    .toISOString()
    .slice(0, 7);
}
function shortMonth(month: string): string {
  return new Date(month.slice(0, 7) + "-01T12:00:00Z")
    .toLocaleDateString("en-GB", {
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    })
    .replace("Sept", "Sep");
}
function prettyDateTime(value: string | null) {
  if (!value) return "Not available";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "Asia/Kolkata",
  });
}

interface MonthRange {
  preset: "current" | "3" | "6" | "12" | "custom";
  start: string;
  end: string;
}

function currentRange(): MonthRange {
  const month = currentMonthIST();
  return { preset: "current", start: month, end: month };
}
function presetRange(preset: MonthRange["preset"]): MonthRange {
  const end = currentMonthIST();
  if (preset === "current") return { preset, start: end, end };
  if (preset === "custom") return { preset, start: end, end };
  return {
    preset,
    start: shiftMonth(end, 1 - Number(preset)),
    end,
  };
}
function rangeLabel(range: MonthRange): string {
  return range.start === range.end
    ? shortMonth(range.start)
    : `${shortMonth(range.start)} – ${shortMonth(range.end)}`;
}
function rangeBounds(range: MonthRange): { from: string; to: string } {
  return {
    from: `${range.start}-01`,
    to: `${range.end}-01`,
  };
}

async function postCompanies<T>(
  body: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<T> {
  const response = await fetch("/api/companies", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      typeof payload?.error === "string"
        ? payload.error
        : "companies_data_unavailable",
    );
  }
  return payload as T;
}

interface BreakdownTarget {
  company: CompanyUsageRow;
  user: CompanyUsageUser | null;
  month: string;
  module: MonthModuleKey;
}

const MONTH_NAMES = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
const PRESETS = [
  ["current", "This month"],
  ["3", "Last 3 months"],
  ["6", "Last 6 months"],
  ["12", "Last 12 months"],
  ["custom", "Custom range"],
] as const;

function monthValue(months: CalendarMonthUsage[], month: string) {
  return months.find(item => item.month.slice(0, 7) === month.slice(0, 7));
}
function moduleLabel(key: MonthModuleKey) {
  return MONTH_MODULES.find(module => module.key === key)?.label ?? key;
}

export default function CompaniesDashboard() {
  const [query, setQuery] = useState("");
  const [deferredQuery, setDeferredQuery] = useState("");
  const [integration, setIntegration] = useState("all");
  const [usage, setUsage] = useState<UsageFilter>("all");
  const [sort, setSort] = useState<SortKey>("integration_month");
  const [direction, setDirection] = useState<SortDirection>("desc");
  const [range, setRange] = useState<MonthRange>(() => currentRange());
  const [draft, setDraft] = useState<MonthRange>(() => currentRange());
  const [year, setYear] = useState(() => Number(currentMonthIST().slice(0, 4)));
  const [editing, setEditing] = useState<"start" | "end" | null>(null);
  const [awaitingEnd, setAwaitingEnd] = useState(false);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [dateOpen, setDateOpen] = useState(false);
  const [data, setData] = useState<CompanyUsageResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [target, setTarget] = useState<BreakdownTarget | null>(null);
  const [breakdown, setBreakdown] = useState<ModuleBreakdownResponse | null>(null);
  const [breakdownLoading, setBreakdownLoading] = useState(false);
  const [announcement, setAnnouncement] = useState("");

  const dialogRef = useRef<HTMLDialogElement | null>(null);
  const helpRef = useRef<HTMLDialogElement | null>(null);
  const [monthlyInfoOpen, setMonthlyInfoOpen] = useState(false);
  const monthlyInfoTrigger = useRef<HTMLButtonElement | null>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const searchRef = useRef<HTMLInputElement | null>(null);
  const dateTriggerRef = useRef<HTMLButtonElement | null>(null);
  const datePanelRef = useRef<HTMLDivElement | null>(null);
  const [datePosition, setDatePosition] = useState({ left: 12, top: 12 });

  const bounds = useMemo(() => rangeBounds(range), [range]);
  const label = useMemo(() => rangeLabel(range), [range]);
  const currentMonth = currentMonthIST();
  const filterCount =
    Number(usage !== "all") + Number(integration !== "all");
  const minMonth =
    data?.data_start?.slice(0, 7) ?? DATA_START_MONTH;

  useEffect(() => {
    const timer = setTimeout(() => setDeferredQuery(query), 250);
    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    if (!dateOpen) return;
    const position = () => {
      const trigger = dateTriggerRef.current;
      const panel = datePanelRef.current;
      if (!trigger || !panel) return;
      const anchor = trigger.getBoundingClientRect();
      const rect = panel.getBoundingClientRect();
      setDatePosition({
        left: Math.max(
          12,
          Math.min(
            anchor.right - rect.width,
            window.innerWidth - rect.width - 12,
          ),
        ),
        top: Math.max(
          12,
          Math.min(
            anchor.bottom + 8,
            window.innerHeight - rect.height - 12,
          ),
        ),
      });
    };
    const frame = requestAnimationFrame(position);
    window.addEventListener("resize", position);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("resize", position);
    };
  }, [dateOpen]);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    postCompanies<CompanyUsageResponse>(
      {
        action: "list",
        query: deferredQuery,
        integration,
        usage,
        sort,
        direction,
        from: bounds.from,
        to: bounds.to,
      },
      controller.signal,
    )
      .then(result => {
        setData(result);
        setExpanded(new Set());
      })
      .catch(err => {
        if (err.name !== "AbortError") {
          setError(String(err.message || err));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [
    deferredQuery,
    integration,
    usage,
    sort,
    direction,
    bounds.from,
    bounds.to,
  ]);

  useEffect(() => {
    if (!target) return;
    const controller = new AbortController();
    setBreakdown(null);
    setBreakdownLoading(true);
    postCompanies<ModuleBreakdownResponse>(
      {
        action: "breakdown",
        company_id: target.company.id,
        user_id: target.user?.id ?? null,
        module: target.module,
        month: target.month.slice(0, 7) + "-01",
      },
      controller.signal,
    )
      .then(setBreakdown)
      .catch(() => setBreakdown(null))
      .finally(() => {
        if (!controller.signal.aborted) setBreakdownLoading(false);
      });
    return () => controller.abort();
  }, [target]);

  const openBreakdown = (
    company: CompanyUsageRow,
    user: CompanyUsageUser | null,
    month: string,
    module: MonthModuleKey,
    trigger: HTMLElement,
  ) => {
    triggerRef.current = trigger;
    setTarget({ company, user, month, module });
    requestAnimationFrame(() => {
      dialogRef.current?.showModal();
      document.body.classList.add("modal-open");
    });
  };

  const closeBreakdown = () => dialogRef.current?.close();
  const onDialogClose = () => {
    setTarget(null);
    setBreakdown(null);
    document.body.classList.remove("modal-open");
    triggerRef.current?.focus();
  };

  const toggleCompany = (id: string) =>
    setExpanded(current => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const sortBy = (key: SortKey) => {
    setSort(key);
    setDirection(current =>
      key === sort
        ? current === "asc"
          ? "desc"
          : "asc"
        : key === "integration_month"
          ? "desc"
          : "asc",
    );
  };

  const applyRange = (next: MonthRange) => {
    setRange({ ...next });
    setDateOpen(false);
    setAnnouncement(`Integration months changed to ${rangeLabel(next)}.`);
  };

  const chooseMonth = (month: string) => {
    const start = draft.start || month;
    if (editing === "start") {
      setDraft({
        preset: "custom",
        start: month,
        end: draft.end && draft.end >= month ? draft.end : month,
      });
      setEditing(null);
      setAwaitingEnd(true);
    } else if (editing === "end" || awaitingEnd) {
      setDraft({
        preset: "custom",
        start: start < month ? start : month,
        end: start < month ? month : start,
      });
      setEditing(null);
      setAwaitingEnd(false);
    } else {
      setDraft({ preset: "custom", start: month, end: month });
      setEditing(null);
      setAwaitingEnd(true);
    }
  };

  const cohortSummary = useMemo(
    () =>
      (data?.months ?? []).map(month => {
        const totals = { ap: 0, ar: 0, transactions: 0, gst: 0 };
        let availableCompanies = 0;
        for (const company of data?.rows ?? []) {
          const value = monthValue(company.months, month);
          if (!value?.available) continue;
          availableCompanies += 1;
          for (const module of MONTH_MODULES) {
            totals[module.key] += value.totals[module.key] ?? 0;
          }
        }
        return { month, availableCompanies, totals };
      }),
    [data],
  );

  const matrixCell = (
    company: CompanyUsageRow,
    user: CompanyUsageUser | null,
    month: string,
    module: MonthModuleKey,
  ) => {
    const source = user?.months ?? company.months;
    const usageMonth = monthValue(source, month);
    if (!usageMonth?.available) {
      return (
        <td
          className="numeric companies-month-future"
          key={`${month}-${module}`}
        >
          <span title="This company had not integrated yet.">–</span>
        </td>
      );
    }

    const value = usageMonth.totals[module] ?? 0;
    return (
      <td className="numeric" key={`${month}-${module}`}>
        <button
          type="button"
          className={`companies-module-button ${value === 0 ? "is-zero" : ""}`}
          onClick={event =>
            openBreakdown(
              company,
              user,
              month,
              module,
              event.currentTarget,
            )
          }
          aria-label={`${shortMonth(month)} ${moduleLabel(module)} usage for ${user?.email ?? company.name}: ${number.format(value)} events. View breakdown.`}
        >
          {number.format(value)}
        </button>
      </td>
    );
  };

  const matrixCells = (
    company: CompanyUsageRow,
    user: CompanyUsageUser | null,
  ) => (
    <>
      {(data?.months ?? []).flatMap(month =>
        MONTH_MODULES.map(module =>
          matrixCell(company, user, month, module.key),
        ),
      )}
    </>
  );

  const totalColumns =
    3 + (data?.months.length ?? 1) * MONTH_MODULES.length;
  const tableMinWidth =
    440 + Math.max(1, data?.months.length ?? 1) * 264;

  return (
    <div className="companies-shell">
      <ProductMetricsHeader
        current="companies"
      />

      <main className="companies-page" id="companies-main">
        <div className="page-heading companies-page-heading">
          <div className="companies-title-block">
            <h1>Companies</h1>
            <p>Monthly product adoption by integration cohort</p>
          </div>
          <div className="global-controls">
            {range.preset !== "current" ? (
              <button
                className="reset-range"
                type="button"
                onClick={() => applyRange(currentRange())}
              >
                Reset
              </button>
            ) : null}
            <span className="global-control-label">
              Integration month
            </span>
            <button
              ref={dateTriggerRef}
              type="button"
              className="ui-control date-trigger"
              aria-label={`Integration month: ${label}`}
              aria-haspopup="dialog"
              aria-expanded={dateOpen}
              onClick={() => {
                setDraft({ ...range });
                setYear(Number(range.end.slice(0, 4)));
                setEditing(null);
                setAwaitingEnd(false);
                setDateOpen(open => !open);
              }}
            >
              <Icon name="calendar" />
              <span>{label}</span>
              <span className="chevron">
                <Icon name="down" />
              </span>
            </button>
          </div>
        </div>

        <div className="metrics-section-kicker" aria-label="Company activity section">
          <span>Company usage</span>
          <span className="metrics-section-description">Monthly modules · Integration cohorts</span>
        </div>

        <section
          className="companies-records po-record-layout companies-monthly-records companies-grid-card"
          aria-label="Monthly company usage"
        >
          <div className="po-record-toolbar companies-command-bar">
            <div className="companies-toolbar-meta">
              <strong>{loading && !data ? "Loading companies…" : error && !data ? "Data unavailable" : number.format(data?.total ?? 0) + " companies"}</strong>
              <span>{label} cohort · updated {prettyDateTime(data?.source_watermark_at ?? null)}
                {range.start <= "2026-07" && range.end >= "2026-05"
                  ? " · May–July integration tracking incomplete" : ""}
              </span>
            </div>
            <div className="po-record-tools">
              <MetricsInfoButton
                label="How monthly company module usage is counted"
                onClick={event => {
                  monthlyInfoTrigger.current = event.currentTarget;
                  setMonthlyInfoOpen(true);
                }}
              />
              <div className="po-search">
                <Icon name="search" />
                <input
                  ref={searchRef}
                  type="search"
                  value={query}
                  placeholder="Search companies or users"
                  aria-label="Search companies or users"
                  autoComplete="off"
                  onChange={event =>
                    setQuery(event.currentTarget.value)
                  }
                />
                {query ? (
                  <button
                    type="button"
                    aria-label="Clear company search"
                    onClick={() => {
                      setQuery("");
                      searchRef.current?.focus();
                    }}
                  >
                    <Icon name="close" />
                  </button>
                ) : null}
              </div>

              <div className="po-filter-wrap companies-filter-wrap">
                <button
                  type="button"
                  className={`ui-control companies-filter-trigger ${filterCount ? "has-filters" : ""}`}
                  aria-expanded={filtersOpen}
                  onClick={() =>
                    setFiltersOpen(open => !open)
                  }
                >
                  <Icon name="filter" />
                  <span>Filters</span>
                  {filterCount ? <span className="companies-filter-badge">{filterCount}</span> : null}
                </button>

                {filtersOpen ? (
                  <div className="companies-filter-popover po-filters">
              <div className="po-filter-head">
                <strong>Filter companies</strong>
                <button
                  type="button"
                  disabled={filterCount === 0}
                  onClick={() => {
                    setUsage("all");
                    setIntegration("all");
                  }}
                >
                  Reset
                </button>
              </div>

              <label htmlFor="companies-usage-filter">
                Usage in selected months
              </label>
              <span className="ui-select-host">
                <select
                  id="companies-usage-filter"
                  className="ui-control ui-select-trigger"
                  value={usage}
                  onChange={event =>
                    setUsage(
                      event.currentTarget.value as UsageFilter,
                    )
                  }
                >
                  <option value="all">
                    All integrated companies
                  </option>
                  <option value="active">
                    With module usage
                  </option>
                  <option value="inactive">
                    No module usage
                  </option>
                </select>
              </span>

              <label htmlFor="companies-integration-filter">
                Integration
              </label>
              <span className="ui-select-host">
                <select
                  id="companies-integration-filter"
                  className="ui-control ui-select-trigger"
                  value={integration}
                  onChange={event =>
                    setIntegration(event.currentTarget.value)
                  }
                >
                  <option value="all">All integrations</option>
                  <option value="Tally">Tally</option>
                  <option value="Zoho Books">
                    Zoho Books
                  </option>
                  <option value="Unknown">Unknown</option>
                </select>
              </span>

              <div className="po-filter-note">
                The cohort is based on first successful integration
                month. Usage columns are calendar months.
              </div>
                  </div>
                ) : null}
              </div>
            </div>
          </div>

          <div
            className="po-record-scroll companies-monthly-scroll"
            role="region"
            tabIndex={0}
            aria-label="Company and user monthly usage, scroll horizontally for months"
          >
            {!data && loading ? (
              <div className="companies-loading" role="status">
                Loading company usage…
              </div>
            ) : !data && error ? (
              <div className="companies-error" role="alert">
                <div>
                  <strong>
                    Live company data could not be loaded.
                  </strong>
                  <span>
                    The secure data bridge is unavailable ({error}).
                    No fixture values are shown.
                  </span>
                </div>
              </div>
            ) : (
              <>
                {error ? (
                  <div
                    className="companies-inline-error"
                    role="status"
                  >
                    Couldn’t refresh this view. Keeping the last
                    loaded results.
                  </div>
                ) : null}

                <table
                  className="po-user-table companies-table companies-monthly-table"
                  aria-label="Monthly company module usage"
                  aria-busy={loading}
                  style={{ minWidth: tableMinWidth }}
                >
                  <thead>
                    <tr className="companies-month-header">
                      <th scope="col">
                        <span className="sr-only">
                          Expand users
                        </span>
                      </th>
                      <th
                        scope="col"
                        aria-sort={
                          sort === "integration_month"
                            ? direction === "asc"
                              ? "ascending"
                              : "descending"
                            : undefined
                        }
                      >
                        <button
                          type="button"
                          onClick={() =>
                            sortBy("integration_month")
                          }
                        >
                          Integration month
                          <Icon
                            name={
                              sort === "integration_month"
                                ? direction === "asc"
                                  ? "up"
                                  : "down"
                                : "sort"
                            }
                          />
                        </button>
                      </th>
                      <th
                        scope="col"
                        aria-sort={
                          sort === "name"
                            ? direction === "asc"
                              ? "ascending"
                              : "descending"
                            : undefined
                        }
                      >
                        <button
                          type="button"
                          onClick={() => sortBy("name")}
                        >
                          Company
                          <Icon
                            name={
                              sort === "name"
                                ? direction === "asc"
                                  ? "up"
                                  : "down"
                                : "sort"
                            }
                          />
                        </button>
                      </th>

                      {(data?.months ?? []).map(month => (
                        <th
                          key={month}
                          scope="colgroup"
                          colSpan={4}
                          className="companies-month-group"
                        >
                          {shortMonth(month)}
                        </th>
                      ))}
                    </tr>

                    <tr className="companies-module-header">
                      <th
                        aria-hidden="true"
                        className="companies-frozen-header-spacer"
                      />
                      <th
                        aria-hidden="true"
                        className="companies-frozen-header-spacer"
                      />
                      <th
                        aria-hidden="true"
                        className="companies-frozen-header-spacer"
                      />

                      {(data?.months ?? []).flatMap(month =>
                        MONTH_MODULES.map(module => (
                          <th
                            key={`${month}-${module.key}`}
                            scope="col"
                            className={`numeric companies-module-head companies-module-${module.key}`}
                          >
                            {module.label}
                          </th>
                        )),
                      )}
                    </tr>
                  </thead>

                  <tbody>
                    {(data?.rows ?? []).length ? (
                      data!.rows.flatMap(company => {
                        const open = expanded.has(company.id);
                        const parent = (
                          <tr
                            key={company.id}
                            className={`po-user-row companies-company-row ${open ? "po-expanded" : ""}`}
                            data-company-id={company.id}
                          >
                            <td className="companies-expander-cell">
                              <button
                                className="po-expander"
                                type="button"
                                aria-label={`${open ? "Collapse" : "Expand"} users for ${company.name}`}
                                aria-expanded={open}
                                onClick={() =>
                                  toggleCompany(company.id)
                                }
                              >
                                <Icon name={open ? "down" : "right"} />
                              </button>
                            </td>
                            <td className="companies-integration-month">
                              {shortMonth(
                                company.integration_month,
                              )}
                            </td>
                            <td
                              className="companies-company-cell"
                              title={`${company.name} · ${company.id}`}
                            >
                              <span className="companies-company-name">
                                {company.name}
                              </span>
                              {company.is_test ? (
                                <span className="po-status neutral">
                                  Test
                                </span>
                              ) : null}
                              <span className="integration-tag">
                                {company.integration}
                              </span>
                            </td>
                            {matrixCells(company, null)}
                          </tr>
                        );

                        if (!open) return [parent];

                        const children = company.users.length
                          ? company.users.map(user => (
                              <tr
                                key={`${company.id}-${user.id}`}
                                className="companies-nested-user-row"
                              >
                                <td className="companies-expander-cell" />
                                <td className="companies-user-month" />
                                <td
                                  className="companies-user-email"
                                  title={user.email}
                                >
                                  {user.email}
                                </td>
                                {matrixCells(company, user)}
                              </tr>
                            ))
                          : [
                              <tr
                                key={`${company.id}-empty-users`}
                                className="companies-nested-user-row"
                              >
                                <td />
                                <td />
                                <td className="companies-user-email">
                                  No observed users after integration.
                                </td>
                                <td colSpan={Math.max(4, totalColumns - 3)} />
                              </tr>,
                            ];

                        return [parent, ...children];
                      })
                    ) : (
                      <tr>
                        <td colSpan={totalColumns}>
                          <div className="po-empty">
                            <strong>
                              No integrated companies match this
                              view
                            </strong>
                            <span>
                              Try a different search, filter or
                              integration month.
                            </span>
                          </div>
                        </td>
                      </tr>
                    )}
                  </tbody>

                  <tfoot>
                    <tr className="companies-total-row">
                      <td />
                      <td className="companies-total-label">
                        Total
                      </td>
                      <td className="companies-total-count">
                        {number.format(data?.total ?? 0)} companies
                      </td>
                      {(data?.months ?? []).flatMap(month => {
                        const summary = cohortSummary.find(
                          item =>
                            item.month.slice(0, 7) ===
                            month.slice(0, 7),
                        );
                        return MONTH_MODULES.map(module => (
                          <td
                            className="numeric"
                            key={`total-${month}-${module.key}`}
                          >
                            {summary?.availableCompanies
                              ? number.format(
                                  summary.totals[module.key],
                                )
                              : "–"}
                          </td>
                        ));
                      })}
                    </tr>
                  </tfoot>
                </table>

                {loading ? (
                  <div
                    className="companies-refreshing"
                    role="status"
                  >
                    Loading…
                  </div>
                ) : null}
              </>
            )}
          </div>
        </section>

      </main>

      {dateOpen ? (
        <div
          ref={datePanelRef}
          className="date-popover ui-menu-surface"
          role="dialog"
          aria-labelledby="companies-date-title"
          aria-describedby="companies-date-instructions"
          style={{
            left: datePosition.left,
            top: datePosition.top,
          }}
        >
          <div className="date-popover-heading">
            <div>
              <h2 id="companies-date-title">
                Integration month
              </h2>
              <span>
                Choose one cohort month or a month range
              </span>
            </div>
            <button
              className="icon-button"
              type="button"
              aria-label="Close integration month picker"
              onClick={() => setDateOpen(false)}
            >
              <Icon name="close" />
            </button>
          </div>

          <div className="date-picker-body">
            <div
              className="date-presets"
              role="group"
              aria-label="Integration month presets"
            >
              {PRESETS.map(([value, text]) => {
                const next =
                  value === "custom"
                    ? { ...draft, preset: value }
                    : presetRange(value);
                return (
                  <button
                    key={value}
                    type="button"
                    className="date-preset"
                    aria-pressed={draft.preset === value}
                    onClick={() => {
                      setDraft(next);
                      setAwaitingEnd(false);
                      setEditing(null);
                    }}
                  >
                    <span>
                      <strong>{text}</strong>
                      <small>
                        {value === "custom"
                          ? "Choose start and end months"
                          : rangeLabel(next)}
                      </small>
                    </span>
                    <span className="preset-check">
                      <Icon name="check" />
                    </span>
                  </button>
                );
              })}
            </div>

            <div className="month-picker">
              <div className="range-fields">
                <button
                  type="button"
                  className={`range-field ${editing === "start" ? "is-picking" : ""}`}
                  onClick={() => {
                    setDraft({
                      ...draft,
                      preset: "custom",
                    });
                    setEditing("start");
                    setAwaitingEnd(false);
                  }}
                >
                  <span>Start month</span>
                  <strong>{shortMonth(draft.start)}</strong>
                </button>
                <Icon name="arrow" />
                <button
                  type="button"
                  className={`range-field ${editing === "end" || awaitingEnd ? "is-picking" : ""}`}
                  onClick={() => {
                    setDraft({
                      ...draft,
                      preset: "custom",
                    });
                    setEditing("end");
                    setAwaitingEnd(false);
                  }}
                >
                  <span>End month</span>
                  <strong>{shortMonth(draft.end)}</strong>
                </button>
              </div>

              <div className="month-picker-header">
                <strong>{year}</strong>
                <div>
                  <button
                    className="icon-button"
                    type="button"
                    aria-label="Previous year"
                    disabled={year <= Number(minMonth.slice(0, 4))}
                    onClick={() => setYear(year - 1)}
                  >
                    <Icon name="left" />
                  </button>
                  <button
                    className="icon-button"
                    type="button"
                    aria-label="Next year"
                    disabled={
                      year >=
                      Number(currentMonth.slice(0, 4))
                    }
                    onClick={() => setYear(year + 1)}
                  >
                    <Icon name="right" />
                  </button>
                </div>
              </div>

              <div
                className="month-grid"
                role="group"
                aria-label="Select integration months"
              >
                {MONTH_NAMES.map((name, index) => {
                  const key = `${year}-${String(index + 1).padStart(2, "0")}`;
                  const selected =
                    key >= draft.start &&
                    key <= draft.end;
                  return (
                    <button
                      key={key}
                      type="button"
                      className={`month-button ${selected ? "in-range" : ""} ${selected && (key === draft.start || key === draft.end) ? "is-endpoint" : ""} ${key === currentMonth ? "is-current" : ""}`}
                      aria-label={shortMonth(key)}
                      aria-pressed={selected}
                      disabled={
                        key > currentMonth ||
                        key < minMonth
                      }
                      onClick={() => chooseMonth(key)}
                    >
                      {name}
                    </button>
                  );
                })}
              </div>

              <p
                className="month-picker-instructions"
                id="companies-date-instructions"
              >
                {awaitingEnd
                  ? "Choose an end month, or Apply to use just this month."
                  : "Choose one month, or choose another to create a range."}
              </p>
            </div>
          </div>

          <div className="date-scope-note">
            <Icon name="info" />
            <span>
              Companies are selected by first successful
              integration month. Usage columns are calendar
              months; the integration month starts at the actual
              integration timestamp.
            </span>
          </div>

          <div className="date-picker-footer">
            <span role="status">{rangeLabel(draft)}</span>
            <div>
              <button
                className="ui-control"
                type="button"
                onClick={() => setDateOpen(false)}
              >
                Cancel
              </button>
              <button
                className="ui-control ui-primary"
                type="button"
                onClick={() => applyRange(draft)}
              >
                Apply
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <div
        className="sr-only"
        role="status"
        aria-live="polite"
      >
        {announcement}
      </div>

      <dialog
        ref={dialogRef}
        className="companies-breakdown"
        aria-labelledby="companies-breakdown-title"
        onClose={onDialogClose}
      >
        <div className="companies-breakdown-layout">
          <header className="dialog-header">
            <div>
              <p className="dialog-eyebrow">
                {target
                  ? `${shortMonth(target.month)} · ${moduleLabel(target.module)}`
                  : "Module usage"}
              </p>
              <h2
                className="dialog-title"
                id="companies-breakdown-title"
              >
                {target?.company.name ??
                  "Usage breakdown"}
              </h2>
              <p className="dialog-subtitle">
                {target?.user
                  ? `${target.user.email} · `
                  : "Company total · "}
                {target
                  ? `${shortMonth(target.month)} calendar-month usage`
                  : ""}
              </p>
            </div>
            <button
              className="close-button"
              type="button"
              aria-label="Close usage breakdown"
              onClick={closeBreakdown}
            >
              <Icon name="close" />
            </button>
          </header>

          <div className="companies-breakdown-summary">
            <span>
              <strong>
                {breakdownLoading
                  ? "…"
                  : number.format(breakdown?.total ?? 0)}
              </strong>{" "}
              events
            </span>
            {breakdown?.item_total != null ? (
              <span>
                <strong>
                  {number.format(breakdown.item_total)}
                </strong>{" "}
                affected items reported by instrumented events
              </span>
            ) : (
              <span>
                No instrumented item volume for this selection
              </span>
            )}
          </div>

          <div
            className="companies-breakdown-wrap"
            role="region"
            tabIndex={0}
            aria-label="Module event breakdown"
          >
            {breakdownLoading ? (
              <div className="companies-loading">
                Loading event breakdown…
              </div>
            ) : !breakdown ? (
              <div className="companies-error">
                <div>
                  <strong>Breakdown unavailable</strong>
                  <span>
                    The secure data bridge is unavailable. No
                    fallback data is shown.
                  </span>
                </div>
              </div>
            ) : (
              <table className="companies-breakdown-table">
                <thead>
                  <tr>
                    <th scope="col">Event / subtype</th>
                    <th scope="col">Status</th>
                    <th scope="col" className="numeric">
                      Events
                    </th>
                    <th scope="col" className="numeric">
                      Affected items
                    </th>
                    <th scope="col">
                      Latest activity
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {breakdown.rows.length ? (
                    breakdown.rows.map((row, index) => (
                      <tr
                        key={`${row.event}-${row.subtype}-${row.status}-${index}`}
                      >
                        <td>
                          {row.event}
                          {row.subtype ? (
                            <span className="companies-breakdown-subtype">
                              {row.subtype}
                            </span>
                          ) : null}
                        </td>
                        <td>
                          {row.status ? (
                            <span
                              className={`companies-breakdown-status ${row.status.toLowerCase() === "failed" ? "failed" : ""}`}
                            >
                              {row.status}
                            </span>
                          ) : (
                            "–"
                          )}
                        </td>
                        <td className="numeric">
                          {number.format(row.count)}
                        </td>
                        <td className="numeric">
                          {row.items == null ? (
                            <span title="Item volume is not instrumented for this event.">
                              –
                            </span>
                          ) : (
                            number.format(row.items)
                          )}
                        </td>
                        <td>
                          {prettyDateTime(row.latest_at)}
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={5}>
                        <div className="po-empty">
                          <strong>
                            No events in this module
                          </strong>
                          <span>
                            This is a real zero for this
                            company/user and calendar month.
                          </span>
                        </div>
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            )}
          </div>

          <footer className="companies-breakdown-foot">
            <span>
              {breakdown?.window_start
                ? `${prettyDateTime(breakdown.window_start)} → ${prettyDateTime(breakdown.window_end)}`
                : target
                  ? shortMonth(target.month)
                  : ""}
            </span>
            <span>
              {target?.user ? "User scope" : "Company scope"}
            </span>
          </footer>
        </div>
      </dialog>

      {monthlyInfoOpen ? (
        <MetricsInfoDialog
          definition={metricsInfoDefinitions.companies_monthly}
          onClose={() => {
            setMonthlyInfoOpen(false);
            requestAnimationFrame(() => monthlyInfoTrigger.current?.focus({ preventScroll: true }));
          }}
        />
      ) : null}

      <dialog
        ref={helpRef}
        className="info-dialog"
        aria-labelledby="companies-help-title"
      >
        <header className="dialog-header">
          <h2
            className="dialog-title"
            id="companies-help-title"
          >
            Monthly company usage
          </h2>
          <button
            className="close-button"
            type="button"
            aria-label="Close metric definitions"
            onClick={() => helpRef.current?.close()}
          >
            <Icon name="close" />
          </button>
        </header>
        <div className="info-body">
          <section className="definition-block">
            <h3>Integration cohort</h3>
            <p>
              A company belongs to the calendar month of its first
              successful integration. Selecting Aug–Oct includes
              companies first integrated in Aug, Sep or Oct.
            </p>
          </section>
          <section className="definition-block">
            <h3>Month usage</h3>
            <p>
              AP, AR, TXN and GST are counted in calendar months
              using Asia/Kolkata boundaries. In the integration
              month, only events at or after the actual integration
              timestamp are counted.
            </p>
          </section>
          <section className="definition-block">
            <h3>Zero versus dash</h3>
            <p>
              Zero means the company was already integrated but
              recorded no qualifying events for that module in the
              month. A dash means the company had not integrated
              yet.
            </p>
          </section>
          <section className="definition-block">
            <h3>Nested users</h3>
            <p>
              Expand a company to see observed non-internal users.
              User cells use the same calendar-month and module
              definitions as the parent company.
            </p>
          </section>
        </div>
      </dialog>
    </div>
  );
}
