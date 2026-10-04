"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  MODULES,
  type CompanyUsageResponse,
  type CompanyUsageRow,
  type CompanyUsageUser,
  type ModuleBreakdownResponse,
  type ModuleKey,
  type SortDirection,
  type SortKey,
  type Totals,
  type UsageFilter,
} from "../../lib/companies/types";

type IconName = "grid" | "trend" | "help" | "calendar" | "down" | "up" | "left" | "right" | "arrow" | "close" | "search" | "filter" | "plus" | "minus" | "sort" | "check" | "info";

function Icon({ name }: { name: IconName }) {
  const paths: Partial<Record<IconName, string>> = {
    trend: "m3 17 6-6 4 4 8-10m-6 0h6v6", down: "m7 10 5 5 5-5", up: "m7 14 5-5 5 5",
    left: "m14 6-6 6 6 6", right: "m10 6 6 6-6 6", arrow: "M5 12h14m-5-5 5 5-5 5",
    close: "m6 6 12 12M18 6 6 18", filter: "M3 4h18l-7 8v7l-4 2v-9z",
    plus: "M5 12h14M12 5v14", minus: "M5 12h14", sort: "M8 4v16m-3-3 3 3 3-3M16 20V4m-3 3 3-3 3 3", check: "m5 12 4 4L19 6",
  };
  return <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
    {name === "grid" ? [[3.5, 3.5], [14.5, 3.5], [3.5, 14.5], [14.5, 14.5]].map(([x, y]) => <rect key={`${x}-${y}`} x={x} y={y} width="6" height="6" rx="1" />)
      : name === "search" ? [<circle key="c" cx="10.5" cy="10.5" r="6.5" />, <path key="p" d="m16 16 4.5 4.5" />]
      : name === "calendar" ? [<rect key="r" x="4" y="5" width="16" height="16" rx="2" />, <path key="p" d="M8 3v4m8-4v4M4 10h16m-12 4h2m4 0h2m-8 3h2" />]
      : name === "help" || name === "info" ? [<circle key="c" cx="12" cy="12" r="9" />, <path key="p" d={name === "help" ? "M9.5 8.7a2.6 2.6 0 0 1 5 1c0 1.8-2.5 2-2.5 3.8M12 16.8v.1" : "M12 10.5v6M12 7.3v.1"} />]
      : <path d={paths[name]} />}
  </svg>;
}

const number = new Intl.NumberFormat("en-US");
const moduleLabel = (key: ModuleKey) => MODULES.find(module => module.key === key)?.label ?? key;

/** Live warehouse history starts here; earlier months are unavailable, not zero. */
const DATA_START_MONTH = "2026-03";
const PAGE_SIZE = 10;

function istMonthNow(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" }).slice(0, 7);
}
function shiftMonth(month: string, offset: number): string {
  const [year, m] = month.split("-").map(Number);
  return new Date(Date.UTC(year, m - 1 + offset, 1)).toISOString().slice(0, 7);
}
function lastDayOfMonth(month: string): string {
  return new Date(Date.parse(shiftMonth(month, 1) + "-01T12:00:00Z") - 86_400_000).toISOString().slice(0, 10);
}
function shortMonth(month: string): string {
  return new Date(month + "-01T12:00:00Z").toLocaleDateString("en-GB", { month: "short", year: "numeric", timeZone: "UTC" }).replace("Sept", "Sep");
}

interface MonthRange { preset: "lifetime" | "3" | "6" | "12" | "custom"; start: string | null; end: string | null }
const LIFETIME: MonthRange = { preset: "lifetime", start: null, end: null };

function presetRange(preset: MonthRange["preset"]): MonthRange {
  if (preset === "lifetime" || preset === "custom") return { ...LIFETIME, preset };
  const end = shiftMonth(istMonthNow(), -1);
  return { preset, start: shiftMonth(end, 1 - Number(preset)), end };
}
function rangeLabel(range: MonthRange): string {
  if (range.preset === "lifetime") return "Lifetime";
  if (!range.start || !range.end) return "Choose months";
  return range.start === range.end ? shortMonth(range.start) : `${shortMonth(range.start)} – ${shortMonth(range.end)}`;
}
/** Month boundaries as Asia/Kolkata calendar days for the server. */
function rangeBounds(range: MonthRange): { from: string | null; to: string | null } {
  if (range.preset === "lifetime" || !range.start || !range.end) return { from: null, to: null };
  const now = istMonthNow();
  const end = range.end > now ? now : range.end;
  return { from: `${range.start}-01`, to: lastDayOfMonth(end) };
}

function prettyDateTime(value: string | null) {
  if (!value) return "Not available";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("en-IN", { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", timeZone: "Asia/Kolkata" });
}

async function postCompanies<T>(body: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
  const response = await fetch("/api/companies", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(typeof payload?.error === "string" ? payload.error : "companies_data_unavailable");
  return payload as T;
}

interface BreakdownTarget { company: CompanyUsageRow; user: CompanyUsageUser | null; module: ModuleKey }

const DASHBOARDS = [
  { name: "Product Overview", description: "Active usage, adoption and workflow health", href: "/overview" },
  { name: "Retention & Churn", description: "Activation, retention and monthly churn", href: "/overview#retention" },
  { name: "Companies", description: "Module usage by company and user", href: "/customer" },
];
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const PRESETS = [["lifetime", "Lifetime"], ["3", "Last 3 months"], ["6", "Last 6 months"], ["12", "Last 12 months"], ["custom", "Custom range"]] as const;

export default function CompaniesDashboard() {
  const [query, setQuery] = useState("");
  const [deferredQuery, setDeferredQuery] = useState("");
  const [integration, setIntegration] = useState("all");
  const [usage, setUsage] = useState<UsageFilter>("all");
  const [sort, setSort] = useState<SortKey>("name");
  const [direction, setDirection] = useState<SortDirection>("asc");
  const [range, setRange] = useState<MonthRange>({ ...LIFETIME });
  const [draft, setDraft] = useState<MonthRange>({ ...LIFETIME });
  const [year, setYear] = useState(() => Number(istMonthNow().slice(0, 4)));
  const [editing, setEditing] = useState<"start" | "end" | null>(null);
  const [awaitingEnd, setAwaitingEnd] = useState(false);
  const [page, setPage] = useState(1);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [menuOpen, setMenuOpen] = useState(false);
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
  const triggerRef = useRef<HTMLElement | null>(null);
  const searchRef = useRef<HTMLInputElement | null>(null);

  const bounds = useMemo(() => rangeBounds(range), [range]);
  const label = useMemo(() => rangeLabel(range), [range]);
  const currentMonth = istMonthNow();
  const filterCount = Number(usage !== "all") + Number(integration !== "all");

  useEffect(() => {
    const timer = setTimeout(() => setDeferredQuery(query), 250);
    return () => clearTimeout(timer);
  }, [query]);
  useEffect(() => { setPage(1); }, [deferredQuery, integration, usage, range]);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true); setError(null);
    postCompanies<CompanyUsageResponse>({
      action: "list", page, query: deferredQuery, integration, usage,
      sort, direction, from: bounds.from, to: bounds.to,
    }, controller.signal)
      .then(result => { setData(result); setExpanded(new Set()); })
      .catch(err => { if (err.name !== "AbortError") { setData(null); setError(String(err.message || err)); } })
      .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [page, deferredQuery, integration, usage, sort, direction, bounds.from, bounds.to]);

  useEffect(() => {
    if (!target) return;
    const controller = new AbortController();
    setBreakdown(null); setBreakdownLoading(true);
    postCompanies<ModuleBreakdownResponse>({
      action: "breakdown",
      company_id: target.company.id,
      user_id: target.user?.id ?? null,
      module: target.module,
      from: bounds.from, to: bounds.to,
    }, controller.signal)
      .then(setBreakdown)
      .catch(() => setBreakdown(null))
      .finally(() => { if (!controller.signal.aborted) setBreakdownLoading(false); });
    return () => controller.abort();
  }, [target, bounds.from, bounds.to]);

  const openBreakdown = (company: CompanyUsageRow, user: CompanyUsageUser | null, module: ModuleKey, trigger: HTMLElement) => {
    triggerRef.current = trigger;
    setTarget({ company, user, module });
    requestAnimationFrame(() => {
      dialogRef.current?.showModal();
      document.body.classList.add("modal-open");
    });
  };
  const closeBreakdown = () => dialogRef.current?.close();
  const onDialogClose = () => {
    setTarget(null); setBreakdown(null);
    document.body.classList.remove("modal-open");
    triggerRef.current?.focus();
  };
  const toggleCompany = (id: string) => setExpanded(current => {
    const next = new Set(current);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });
  const sortBy = (key: SortKey) => {
    setSort(key);
    setDirection(current => (key === sort ? (current === "asc" ? "desc" : "asc") : "asc"));
    setPage(1);
  };
  const applyRange = (next: MonthRange) => {
    if (next.preset !== "lifetime" && (!next.start || !next.end)) return;
    setRange({ ...next });
    setDateOpen(false);
    setAnnouncement(`Date range changed to ${rangeLabel(next)}.`);
  };
  const chooseMonth = (month: string) => {
    const start = draft.start || month;
    if (editing === "start") {
      setDraft({ preset: "custom", start: month, end: draft.end && draft.end >= month ? draft.end : month });
      setEditing(null); setAwaitingEnd(true);
    } else if (editing === "end" || awaitingEnd) {
      setDraft({ preset: "custom", start: start < month ? start : month, end: start < month ? month : start });
      setEditing(null); setAwaitingEnd(false);
    } else {
      setDraft({ preset: "custom", start: month, end: month });
      setEditing(null); setAwaitingEnd(true);
    }
  };

  const pages = Math.max(1, Math.ceil((data?.total ?? 0) / PAGE_SIZE));
  const pageItems = useMemo(() => {
    const set = new Set<number>([1, pages, page - 1, page, page + 1]);
    return [...set].filter(value => value >= 1 && value <= pages).sort((a, b) => a - b);
  }, [page, pages]);
  const unavailable = !!data && !data.available;

  const moduleButton = (company: CompanyUsageRow, user: CompanyUsageUser | null, module: ModuleKey, value: number) => {
    if (unavailable) {
      return <span title="Data is unavailable for this period." aria-label="Not available">–</span>;
    }
    return <button
      type="button"
      className={`companies-module-button ${value === 0 ? "is-zero" : ""}`}
      onClick={event => openBreakdown(company, user, module, event.currentTarget)}
      aria-label={`${moduleLabel(module)} usage for ${user?.email ?? company.name}: ${number.format(value)} events. View breakdown.`}
    >{number.format(value)}</button>;
  };

  const cells = (company: CompanyUsageRow, user: CompanyUsageUser | null, totals: Totals) => (
    <>
      {MODULES.map(module => (
        <td className="numeric" key={module.key}>{moduleButton(company, user, module.key, totals[module.key])}</td>
      ))}
    </>
  );

  return <div className="companies-shell">
    <header className="app-header">
      <div className="brand-left"><div className="brand"><span className="brand-mark"><Icon name="grid" /></span>AI Accountant</div><span className="brand-divider" /><span className="product-name">Product Metrics</span></div>
      <nav aria-label="Product metrics navigation" className="top-nav">
        <div className="dashboard-switcher">
          <button className="dashboard-trigger ui-control" type="button" aria-haspopup="menu" aria-expanded={menuOpen} onClick={() => setMenuOpen(open => !open)}><Icon name="grid" /><span>Companies</span><Icon name="down" /></button>
          <div className="dashboard-menu ui-menu-surface" role="menu" hidden={!menuOpen}>
            <div className="menu-heading" role="presentation">Dashboards</div>
            {DASHBOARDS.map(item => <a key={item.name} href={item.href} role="menuitemradio" aria-checked={item.name === "Companies"} className={`dashboard-option ${item.name === "Companies" ? "is-current" : ""}`} onClick={event => { if (item.name === "Companies") { event.preventDefault(); setMenuOpen(false); } }}><span className="menu-option-icon"><Icon name={item.name === "Retention & Churn" ? "trend" : "grid"} /></span><span className="menu-option-copy"><strong>{item.name}</strong><small>{item.description}</small></span>{item.name === "Companies" ? <Icon name="check" /> : null}</a>)}
          </div>
        </div>
        <button className="header-help" type="button" aria-label="Metric definitions" title="Metric definitions" onClick={() => helpRef.current?.showModal()}><Icon name="help" /></button>
      </nav>
    </header>

    <main className="companies-page" id="companies-main">
      <div className="page-heading">
        <h1>Companies</h1>
        <div className="global-controls">
          {range.preset !== "lifetime" ? <button className="reset-range" type="button" onClick={() => applyRange({ ...LIFETIME })}>Reset</button> : null}
          <span className="global-control-label">Date range</span>
          <button type="button" className="ui-control date-trigger" aria-label={`Date range: ${label}`} aria-haspopup="dialog" aria-expanded={dateOpen} onClick={() => { setDraft({ ...range }); setYear(Number((range.end || currentMonth).slice(0, 4))); setEditing(null); setAwaitingEnd(false); setDateOpen(open => !open); }}><Icon name="calendar" /><span>{label}</span><span className="chevron"><Icon name="down" /></span></button>
        </div>
      </div>
      <p className="po-context"><Icon name="info" /><span>Real product events · Counts are event occurrences · Click any module value for its event/subevent breakdown.</span></p>

      <section className="companies-records po-record-layout" aria-label="Company module usage">
        <div className="po-record-toolbar">
          <div className="po-record-tools">
            <div className="po-search"><Icon name="search" /><input ref={searchRef} type="search" value={query} placeholder="Search companies or users" aria-label="Search companies or users" autoComplete="off" onChange={event => setQuery(event.currentTarget.value)} />{query ? <button type="button" aria-label="Clear company search" onClick={() => { setQuery(""); searchRef.current?.focus(); }}><Icon name="close" /></button> : null}</div>
            <div className="po-filter-wrap">
              <button type="button" className="ui-control" aria-expanded={filtersOpen} onClick={() => setFiltersOpen(open => !open)}><Icon name="filter" /><span>Filters · {filterCount}</span></button>
              {filtersOpen ? <div className="po-filters">
                <div className="po-filter-head"><strong>Filter companies</strong><button type="button" onClick={() => { setUsage("all"); setIntegration("all"); setPage(1); }}>Reset</button></div>
                <label htmlFor="companies-usage-filter">Module usage</label>
                <span className="ui-select-host"><select id="companies-usage-filter" className="ui-control ui-select-trigger" value={usage} onChange={event => { setUsage(event.currentTarget.value as UsageFilter); setPage(1); }}>
                  <option value="all">All companies</option><option value="active">With usage</option><option value="inactive">No usage</option>
                </select></span>
                <label htmlFor="companies-integration-filter">Integration</label>
                <span className="ui-select-host"><select id="companies-integration-filter" className="ui-control ui-select-trigger" value={integration} onChange={event => { setIntegration(event.currentTarget.value); setPage(1); }}>
                  <option value="all">All integrations</option><option value="Tally">Tally</option><option value="Zoho Books">Zoho Books</option><option value="Unknown">Unknown</option>
                </select></span>
                <div className="po-filter-note">Filters select companies. Their totals and nested user contributions remain unchanged.</div>
              </div> : null}
            </div>
          </div>
        </div>

        <div className="po-record-scroll" role="region" tabIndex={0} aria-label="Company and user module usage, scroll for more columns">
          {loading ? <div className="companies-loading" role="status">Loading company usage…</div>
            : error ? <div className="companies-error" role="alert"><div><strong>Live company data could not be loaded.</strong><span>The secure data bridge is unavailable ({error}). No fixture values are shown.</span></div></div>
            : <table className="po-user-table companies-table" aria-label="Company module usage">
              <thead><tr><th scope="col"><span className="sr-only">Expand users</span></th>
                {[{ key: "name" as const, label: "Company" }, ...MODULES].map(({ key, label }) => (
                  <th key={key} scope="col" className={key === "name" ? "" : "numeric"} aria-sort={sort === key ? (direction === "asc" ? "ascending" : "descending") : undefined}>
                    <button type="button" onClick={() => sortBy(key)} title={`Sort by ${label}`}>{label}<Icon name={sort === key ? (direction === "asc" ? "up" : "down") : "sort"} /></button>
                  </th>
                ))}
              </tr></thead>
              <tbody>{(data?.rows ?? []).length ? data!.rows.flatMap(company => {
                const open = expanded.has(company.id);
                return [
                  <tr key={company.id} className={`po-user-row ${open ? "po-expanded" : ""}`} data-company-id={company.id}>
                    <td><button className="po-expander" type="button" aria-label={`${open ? "Collapse" : "Expand"} users for ${company.name}`} aria-expanded={open} onClick={() => toggleCompany(company.id)}><Icon name={open ? "minus" : "plus"} /></button></td>
                    <td title={`${company.name} · ${company.id}`}>{company.name}{company.is_test ? <span className="po-status neutral" style={{ marginLeft: 8 }}>Test</span> : null}<span className="integration-tag" style={{ marginLeft: 8 }}>{company.integration}</span></td>
                    {cells(company, null, company.totals)}
                  </tr>,
                  open ? <tr key={`${company.id}-users`} className="po-company-detail"><td colSpan={7}><p className="po-company-caption">{number.format(company.users.length)} observed {company.users.length === 1 ? "user" : "users"} · {label}</p>
                    <table className="po-company-subtable companies-user-table" aria-label={`Users for ${company.name}`}><thead><tr><th scope="col">User</th>{MODULES.map(module => <th key={module.key} scope="col">{module.label}</th>)}</tr></thead>
                      <tbody>{company.users.length ? company.users.map(user => <tr key={user.id}><td>{user.email}</td>{cells(company, user, user.totals)}</tr>) : <tr><td colSpan={6}>No attributed module activity in this range.</td></tr>}</tbody></table></td></tr> : null,
                ];
              }) : <tr><td colSpan={7}><div className="po-empty"><strong>No companies match this view</strong><span>Try a different search, filter or date range.</span></div></td></tr>}</tbody>
            </table>}
        </div>

        <footer className="po-record-foot">
          <span role="status">{data && !loading && !error ? (data.total ? `${(page - 1) * PAGE_SIZE + 1}–${Math.min(page * PAGE_SIZE, data.total)} of ${number.format(data.total)} companies` : "0 matching companies") : "…"}</span>
          <nav className="po-pagination" aria-label="Company table pages"><button type="button" disabled={page <= 1} aria-label="Previous page" onClick={() => setPage(page - 1)}><Icon name="left" /></button>{pageItems.flatMap((value, index) => [index > 0 && value - pageItems[index - 1] > 1 ? <span className="page-ellipsis" key={`gap-${value}`} aria-hidden="true">…</span> : null, <button type="button" key={value} aria-label={`Page ${value}`} aria-current={page === value ? "page" : undefined} onClick={() => setPage(value)}>{value}</button>])}<button type="button" disabled={page >= pages} aria-label="Next page" onClick={() => setPage(page + 1)}><Icon name="right" /></button></nav>
        </footer>
      </section>

      <footer className="po-page-footer"><span className="companies-source-note"><Icon name="info" />Source freshness: {prettyDateTime(data?.source_watermark_at ?? null)}{unavailable ? " · Selected range has no warehouse history; values are unavailable, not zero." : ""}</span><span>Company totals and nested users use the same classified events.</span></footer>
    </main>

    {dateOpen ? <div className="date-popover ui-menu-surface" role="dialog" aria-labelledby="companies-date-title" aria-describedby="companies-date-instructions">
      <div className="date-popover-heading"><div><h2 id="companies-date-title">Date range</h2><span>Applies across this dashboard</span></div><button className="icon-button" type="button" aria-label="Close date range picker" onClick={() => setDateOpen(false)}><Icon name="close" /></button></div>
      <div className="date-picker-body">
        <div className="date-presets" role="group" aria-label="Date range presets">
          {PRESETS.map(([value, text]) => <button key={value} type="button" className="date-preset" aria-pressed={draft.preset === value} onClick={() => { setDraft(value === "custom" ? { ...draft, preset: value } : presetRange(value)); setAwaitingEnd(false); setEditing(null); }}><span><strong>{text}</strong><small>{value === "lifetime" ? "All available data" : value === "custom" ? "Select one or more months" : rangeLabel(presetRange(value))}</small></span><span className="preset-check"><Icon name="check" /></span></button>)}
          <p className="preset-footnote">Presets use completed calendar months (Asia/Kolkata).</p>
        </div>
        <div className="month-picker">
          <div className="range-fields">
            <button type="button" className={`range-field ${editing === "start" ? "is-picking" : ""}`} onClick={() => { setDraft({ ...draft, preset: "custom" }); setEditing("start"); setAwaitingEnd(false); }}><span>Start month</span><strong>{draft.preset === "lifetime" ? "All time" : draft.start ? shortMonth(draft.start) : "Choose month"}</strong></button>
            <Icon name="arrow" />
            <button type="button" className={`range-field ${editing === "end" || awaitingEnd ? "is-picking" : ""}`} onClick={() => { setDraft({ ...draft, preset: "custom" }); setEditing("end"); setAwaitingEnd(false); }}><span>End month</span><strong>{draft.preset === "lifetime" ? "Present" : draft.end ? shortMonth(draft.end) : "Choose month"}</strong></button>
          </div>
          <div className="month-picker-header"><strong>{year}</strong><div><button className="icon-button" type="button" aria-label="Previous year" disabled={year <= 2020} onClick={() => setYear(year - 1)}><Icon name="left" /></button><button className="icon-button" type="button" aria-label="Next year" disabled={year >= Number(currentMonth.slice(0, 4))} onClick={() => setYear(year + 1)}><Icon name="right" /></button></div></div>
          <div className="month-grid" role="group" aria-label="Select months">{MONTH_NAMES.map((name, i) => {
            const key = `${year}-${String(i + 1).padStart(2, "0")}`;
            const selected = draft.preset !== "lifetime" && !!draft.start && !!draft.end && key >= draft.start && key <= draft.end;
            return <button key={key} type="button" className={`month-button ${selected ? "in-range" : ""} ${selected && (key === draft.start || key === draft.end) ? "is-endpoint" : ""} ${key === currentMonth ? "is-current" : ""}`} aria-label={shortMonth(key)} aria-pressed={selected} disabled={key > currentMonth || key < DATA_START_MONTH} onClick={() => chooseMonth(key)}>{name}</button>;
          })}</div>
          <p className="month-picker-instructions" id="companies-date-instructions">{awaitingEnd ? "Choose an end month, or Apply to use just this month." : "Choose a month. Choose another to extend the range."}</p>
        </div>
      </div>
      <div className="date-scope-note"><Icon name="info" /><span>Module usage counts actions in the selected months (Asia/Kolkata). Warehouse history starts {shortMonth(DATA_START_MONTH)}; earlier months are unavailable.</span></div>
      <div className="date-picker-footer"><span role="status">{draft.preset === "lifetime" ? "All available data" : rangeLabel(draft)}{draft.end === currentMonth && draft.preset !== "lifetime" ? <span className="partial-period">Current month is partial</span> : null}</span><div><button className="ui-control" type="button" onClick={() => setDateOpen(false)}>Cancel</button><button className="ui-control ui-primary" type="button" disabled={draft.preset !== "lifetime" && (!draft.start || !draft.end)} onClick={() => applyRange(draft)}>Apply</button></div></div>
    </div> : null}

    <div className="sr-only" role="status" aria-live="polite">{announcement}</div>

    <dialog ref={dialogRef} className="companies-breakdown" aria-labelledby="companies-breakdown-title" onClose={onDialogClose}>
      <div className="companies-breakdown-layout">
        <header className="dialog-header"><div><p className="dialog-eyebrow">{target ? moduleLabel(target.module) : "Module usage"}</p><h2 className="dialog-title" id="companies-breakdown-title">{target?.company.name ?? "Usage breakdown"}</h2><p className="dialog-subtitle">{target?.user ? `${target.user.email} · ` : "Company total · "}{label}</p></div><button className="close-button" type="button" aria-label="Close usage breakdown" onClick={closeBreakdown}><Icon name="close" /></button></header>
        <div className="companies-breakdown-summary"><span><strong>{breakdownLoading ? "…" : number.format(breakdown?.total ?? 0)}</strong> events</span>{breakdown?.item_total != null ? <span><strong>{number.format(breakdown.item_total)}</strong> affected items reported by instrumented events</span> : <span>No instrumented item volume for this selection</span>}</div>
        <div className="companies-breakdown-wrap" role="region" tabIndex={0} aria-label="Module event breakdown">
          {breakdownLoading ? <div className="companies-loading">Loading event breakdown…</div>
            : !breakdown ? <div className="companies-error"><div><strong>Breakdown unavailable</strong><span>The secure data bridge is unavailable. No fallback data is shown.</span></div></div>
            : <table className="companies-breakdown-table"><thead><tr><th scope="col">Event / subtype</th><th scope="col">Status</th><th scope="col" className="numeric">Events</th><th scope="col" className="numeric">Affected items</th><th scope="col">Latest activity</th></tr></thead><tbody>{breakdown.rows.length ? breakdown.rows.map((row, index) => <tr key={`${row.event}-${row.subtype}-${row.status}-${index}`}><td>{row.event}{row.subtype ? <span className="companies-breakdown-subtype">{row.subtype}</span> : null}</td><td>{row.status ? <span className={`companies-breakdown-status ${row.status.toLowerCase() === "failed" ? "failed" : ""}`}>{row.status}</span> : "–"}</td><td className="numeric">{number.format(row.count)}</td><td className="numeric">{row.items == null ? <span title="Item volume is not instrumented for this event.">–</span> : number.format(row.items)}</td><td>{prettyDateTime(row.latest_at)}</td></tr>) : <tr><td colSpan={5}><div className="po-empty"><strong>No events in this module</strong><span>This is a real zero for the selected company/user and period.</span></div></td></tr>}</tbody></table>}
        </div>
        <footer className="companies-breakdown-foot"><span>Event count is the top-level usage measure. Item counts are shown separately when instrumentation supplies them.</span><span>{target?.user ? "User scope" : "Company scope"}</span></footer>
      </div>
    </dialog>

    <dialog ref={helpRef} className="info-dialog" aria-labelledby="companies-help-title">
      <header className="dialog-header"><h2 className="dialog-title" id="companies-help-title">Company module usage</h2><button className="close-button" type="button" aria-label="Close metric definitions" onClick={() => helpRef.current?.close()}><Icon name="close" /></button></header>
      <div className="info-body">
        <section className="definition-block"><h3>Activity counts</h3><p>Bills / AP, Invoices / AR, Transactions, GST and Sync count qualifying product events in the selected months (Asia/Kolkata). These are actions, not unique documents. Item volume appears separately in each breakdown where instrumentation supplies it.</p></section>
        <section className="definition-block"><h3>Companies and users</h3><p>Each row is a stable company ID from the analytics population; equal names are never merged. Nested users are observed identities from real events. Company totals equal the sum of nested users plus unattributed activity from the same events, even when a search matches just one user.</p></section>
        <section className="definition-block"><h3>Unavailable is not zero</h3><p>Warehouse history starts {shortMonth(DATA_START_MONTH)}. Earlier months show a dash. Zero means no recorded activity in an available period. Source freshness is shown below the table.</p></section>
      </div>
      <div className="info-footnote">Live Supabase data via the OIDC-gated bridge. The browser never receives database credentials or raw event access.</div>
    </dialog>
  </div>;
}
