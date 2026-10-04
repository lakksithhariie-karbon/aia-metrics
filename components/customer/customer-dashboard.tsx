"use client";

import React, { Component } from "react";
import { customerFixtures } from "../../lib/customer/fixtures";
import {
  aggregateCustomers, EMPTY_FILTERS, filterAndSort, LIFETIME, MODULES, number,
  pageNumbers, presetRange, rangeLabel, shiftMonth, shortMonth, SNAPSHOT_DATE, SOURCE_START,
  type DateRange, type Filters, type SortKey, type Totals, type UsageRow,
} from "../../lib/customer/usage";

type IconName = "grid" | "trend" | "help" | "calendar" | "down" | "up" | "left" | "right" | "arrow" | "close" | "search" | "filter" | "plus" | "minus" | "sort" | "check" | "info";
export function Icon({ name }: { name: IconName }) {
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

const CUSTOMERS = customerFixtures();
const DASHBOARDS = [
  { name: "Product Overview", description: "Active usage, adoption and workflow health", href: "/overview", icon: "grid" as const },
  { name: "Retention & Churn", description: "Activation, retention and monthly churn", href: "/overview#retention", icon: "trend" as const },
  { name: "Customer", description: "Module usage by customer and user", href: "/customer", icon: "grid" as const },
];
const PRESETS = [["lifetime", "Lifetime"], ["3", "Last 3 months"], ["6", "Last 6 months"], ["12", "Last 12 months"], ["custom", "Custom range"]] as const;
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const CURRENT_MONTH = SNAPSHOT_DATE.slice(0, 7);
const PAGE_SIZE = 10;
type Surface = "dashboard" | "filters" | "date";
type SelectKey = "usage" | "integration";
interface State {
  range: DateRange; draft: DateRange; year: number; awaitingEnd: boolean; editing: "start" | "end" | null;
  filters: Filters; sort: SortKey; direction: "asc" | "desc"; page: number; expanded: Set<string>;
  surface: Surface | null; select: SelectKey | null; selectPosition: { left: number; top: number; width: number };
  datePosition: { left: number; top: number }; announcement: string;
}

/** React owns this complete surface. No prototype scripts or HTML injection. */
export default class CustomerDashboard extends Component<Record<string, never>, State> {
  state: State = {
    range: { ...LIFETIME }, draft: { ...LIFETIME }, year: Number(SNAPSHOT_DATE.slice(0, 4)), awaitingEnd: false, editing: null,
    filters: { ...EMPTY_FILTERS }, sort: "name", direction: "asc", page: 1, expanded: new Set(),
    surface: null, select: null, selectPosition: { left: 0, top: 0, width: 220 }, datePosition: { left: 0, top: 0 }, announcement: "",
  };
  private panels: Record<Surface, HTMLElement | null> = { dashboard: null, filters: null, date: null };
  private triggers: Record<Surface, HTMLButtonElement | null> = { dashboard: null, filters: null, date: null };
  private search: HTMLInputElement | null = null;
  private table: HTMLDivElement | null = null;
  private help: HTMLDialogElement | null = null;
  private helpTrigger: HTMLButtonElement | null = null;
  private cacheKey = "";
  private cachedRows: UsageRow[] = [];

  componentDidMount() {
    document.addEventListener("pointerdown", this.onOutside, true);
    document.addEventListener("keydown", this.onDocumentKey, true);
    window.addEventListener("resize", this.onResize);
  }
  componentWillUnmount() {
    document.removeEventListener("pointerdown", this.onOutside, true);
    document.removeEventListener("keydown", this.onDocumentKey, true);
    window.removeEventListener("resize", this.onResize);
    document.body.classList.remove("modal-open");
  }
  private onResize = () => {
    if (this.state.select) this.setState({ select: null });
    if (this.state.surface === "date") this.positionDate();
  };
  private onOutside = (event: PointerEvent) => {
    const { surface } = this.state;
    if (surface && event.target instanceof Node && !this.panels[surface]?.contains(event.target) && !this.triggers[surface]?.contains(event.target)) this.closeSurface(false);
  };
  private closeSurface = (focus = true) => {
    const trigger = this.state.surface ? this.triggers[this.state.surface] : null;
    this.setState({ surface: null, select: null }, () => { if (focus) trigger?.focus(); });
  };
  private showSurface = (surface: Surface) => {
    if (this.state.surface === surface) { this.closeSurface(); return; }
    this.setState({ surface, select: null, draft: { ...this.state.range }, year: Number((this.state.range.end || CURRENT_MONTH).slice(0, 4)), editing: null, awaitingEnd: false }, () => {
      if (surface === "dashboard") this.panels.dashboard?.querySelector<HTMLElement>('[aria-checked="true"]')?.focus();
      if (surface === "date") { this.positionDate(); this.panels.date?.querySelector<HTMLElement>(`[data-preset="${this.state.draft.preset}"]`)?.focus(); }
    });
  };
  private positionDate = () => {
    const panel = this.panels.date, trigger = this.triggers.date;
    if (!panel || !trigger) return;
    const anchor = trigger.getBoundingClientRect(), rect = panel.getBoundingClientRect();
    this.setState({ datePosition: { left: Math.max(12, Math.min(anchor.right - rect.width, window.innerWidth - rect.width - 12)), top: Math.max(12, Math.min(anchor.bottom + 8, window.innerHeight - rect.height - 12)) } });
  };
  private onDocumentKey = (event: KeyboardEvent) => {
    const { surface, select } = this.state;
    const target = event.target instanceof HTMLElement ? event.target : null;
    if (!surface || !target) return;
    if (event.key === "Escape") {
      event.preventDefault(); event.stopImmediatePropagation();
      if (select) this.setState({ select: null }, () => document.getElementById(`customer-${select}-trigger`)?.focus());
      else this.closeSurface();
      return;
    }
    if (select && target.closest('[role="listbox"]')) {
      const items = Array.from(target.closest('[role="listbox"]')!.querySelectorAll<HTMLButtonElement>("button"));
      const i = items.indexOf(target as HTMLButtonElement);
      const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1 : event.key === "ArrowDown" ? (i + 1) % items.length : event.key === "ArrowUp" ? (i + items.length - 1) % items.length : null;
      if (next !== null) { event.preventDefault(); event.stopPropagation(); items[next]?.focus(); }
      if (event.key === "Tab") { event.preventDefault(); this.setState({ select: null }, () => document.getElementById(`customer-${select}-trigger`)?.focus()); }
      return;
    }
    if (surface === "dashboard") {
      const options = Array.from(this.panels.dashboard?.querySelectorAll<HTMLElement>('[role="menuitemradio"]') || []);
      const i = options.indexOf(target);
      const next = event.key === "Home" ? 0 : event.key === "End" ? options.length - 1 : event.key === "ArrowDown" ? (i + 1) % options.length : event.key === "ArrowUp" ? (i + options.length - 1) % options.length : null;
      if (next !== null) { event.preventDefault(); options[next]?.focus(); }
      if (event.key === " ") { event.preventDefault(); target.click(); }
      if (event.key === "Tab") { event.preventDefault(); this.closeSurface(false); (event.shiftKey ? this.triggers.dashboard : this.helpTrigger)?.focus(); }
    }
    if (surface === "date") {
      const month = target.dataset.customerMonth;
      if (month) {
        const offsets: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -3, ArrowDown: 3 };
        const next = event.key in offsets ? shiftMonth(month, offsets[event.key]) : event.key === "Home" ? `${this.state.year}-01` : event.key === "End" ? `${this.state.year}-${this.state.year === 2026 ? "10" : "12"}` : null;
        if (next) { event.preventDefault(); if (next >= "2020-01" && next <= CURRENT_MONTH) this.setState({ year: Number(next.slice(0, 4)) }, () => this.panels.date?.querySelector<HTMLElement>(`[data-customer-month="${next}"]`)?.focus()); }
      }
      if (event.key === "Tab") {
        const items = Array.from(this.panels.date?.querySelectorAll<HTMLButtonElement>("button:not(:disabled)") || []).filter(item => item.getClientRects().length);
        if (event.shiftKey && target === items[0]) { event.preventDefault(); items[items.length - 1]?.focus(); }
        else if (!event.shiftKey && target === items[items.length - 1]) { event.preventDefault(); items[0]?.focus(); }
      }
    }
  };
  private rows() {
    const key = JSON.stringify(this.state.range);
    if (key !== this.cacheKey) { this.cachedRows = aggregateCustomers(CUSTOMERS, this.state.range); this.cacheKey = key; }
    return filterAndSort(this.cachedRows, this.state.filters, this.state.sort, this.state.direction);
  }
  private setFilter = (key: keyof Filters, value: string) => this.setState(state => ({ filters: { ...state.filters, [key]: value }, page: 1, select: null }));
  private sortBy = (sort: SortKey) => this.setState(state => ({ sort, direction: state.sort === sort && state.direction === "asc" ? "desc" : "asc", page: 1 }));
  private toggleRow = (id: string) => this.setState(state => { const expanded = new Set(state.expanded); if (expanded.has(id)) expanded.delete(id); else expanded.add(id); return { expanded }; });
  private goToPage = (page: number) => this.setState({ page }, () => { if (this.table) this.table.scrollTop = 0; });
  private resetFilters = (query = false) => this.setState(state => ({ filters: { ...EMPTY_FILTERS, query: query ? "" : state.filters.query }, page: 1, select: null }));
  private applyRange = (range: DateRange) => {
    if (range.preset !== "lifetime" && (!range.start || !range.end)) return;
    this.setState({ range: { ...range }, page: 1, expanded: new Set(), surface: null, announcement: `Date range changed to ${rangeLabel(range)}.` }, () => this.triggers.date?.focus());
  };
  private chooseMonth = (month: string) => this.setState((state): Pick<State, "draft" | "editing" | "awaitingEnd"> => {
    const start = state.draft.start || month;
    if (state.editing === "start") return { draft: { preset: "custom", start: month, end: state.draft.end && state.draft.end >= month ? state.draft.end : month }, editing: null, awaitingEnd: true };
    if (state.editing === "end" || state.awaitingEnd) return { draft: { preset: "custom", start: start < month ? start : month, end: start < month ? month : start }, editing: null, awaitingEnd: false };
    return { draft: { preset: "custom", start: month, end: month }, editing: null, awaitingEnd: true };
  });
  private openSelect = (key: SelectKey, trigger: HTMLButtonElement) => {
    if (this.state.select === key) { this.setState({ select: null }); return; }
    const rect = trigger.getBoundingClientRect(), width = Math.max(186, rect.width);
    this.setState({ select: key, selectPosition: { left: Math.max(12, Math.min(rect.left, window.innerWidth - width - 12)), top: Math.max(12, Math.min(rect.bottom + 8, window.innerHeight - 145)), width } }, () => document.querySelector<HTMLElement>(`#customer-${key}-listbox [aria-selected="true"]`)?.focus());
  };
  private renderSelect(key: SelectKey, label: string, options: readonly (readonly [string, string])[]) {
    const value = this.state.filters[key], open = this.state.select === key;
    return <div className="customer-select-field" key={key}>
      <label htmlFor={`customer-${key}-trigger`}>{label}</label>
      <span className="ui-select-host">
        <button id={`customer-${key}-trigger`} className="ui-control ui-select-trigger" type="button" role="combobox" aria-label={`${label}: ${options.find(option => option[0] === value)?.[1]}`} aria-expanded={open} aria-controls={`customer-${key}-listbox`} aria-haspopup="listbox" onClick={e => this.openSelect(key, e.currentTarget)} onKeyDown={e => { if (["ArrowDown", "ArrowUp", "Home", "End"].includes(e.key)) { e.preventDefault(); if (!open) this.openSelect(key, e.currentTarget); } }}>
          <span className="ui-select-value">{options.find(option => option[0] === value)?.[1]}</span><Icon name="down" />
        </button>
      </span>
      <div hidden={!open} id={`customer-${key}-listbox`} className="ui-select-menu ui-menu-surface" role="listbox" aria-label={label} style={this.state.selectPosition}>
        {options.map(([keyValue, text]) => <button key={keyValue} type="button" className="ui-select-option" role="option" aria-selected={value === keyValue} tabIndex={-1} onClick={() => { this.setFilter(key, keyValue); document.getElementById(`customer-${key}-trigger`)?.focus(); }}><span><strong>{text}</strong></span><Icon name="check" /></button>)}
      </div>
    </div>;
  }
  private renderDatePanel() {
    const { draft, year, editing, awaitingEnd } = this.state;
    return <div ref={node => { this.panels.date = node; }} className="date-popover ui-menu-surface" id="customer-date-panel" role="dialog" aria-labelledby="customer-date-title" aria-describedby="customer-date-instructions" hidden={this.state.surface !== "date"} style={this.state.datePosition}>
      <div className="date-popover-heading"><div><h2 id="customer-date-title">Date range</h2><span>Applies across this dashboard</span></div><button className="icon-button" type="button" aria-label="Close date range picker" onClick={() => this.closeSurface()}><Icon name="close" /></button></div>
      <div className="date-picker-body">
        <div className="date-presets" role="group" aria-label="Date range presets">
          {PRESETS.map(([value, label]) => <button key={value} type="button" className="date-preset" data-preset={value} aria-pressed={draft.preset === value} onClick={() => this.setState({ draft: value === "custom" ? { ...draft, preset: value } : presetRange(value), awaitingEnd: false, editing: null })}><span><strong>{label}</strong><small>{value === "lifetime" ? "All available data" : value === "custom" ? "Select one or more months" : rangeLabel(presetRange(value))}</small></span><span className="preset-check"><Icon name="check" /></span></button>)}
          <p className="preset-footnote">Presets use completed calendar months.</p>
        </div>
        <div className="month-picker">
          <div className="range-fields">
            <button type="button" className={`range-field ${editing === "start" ? "is-picking" : ""}`} onClick={() => this.setState({ draft: { ...draft, preset: "custom" }, editing: "start", awaitingEnd: false })}><span>Start month</span><strong>{draft.preset === "lifetime" ? "All time" : draft.start ? shortMonth(draft.start) : "Choose month"}</strong></button>
            <Icon name="arrow" />
            <button type="button" className={`range-field ${editing === "end" || awaitingEnd ? "is-picking" : ""}`} onClick={() => this.setState({ draft: { ...draft, preset: "custom" }, editing: "end", awaitingEnd: false })}><span>End month</span><strong>{draft.preset === "lifetime" ? "Present" : draft.end ? shortMonth(draft.end) : "Choose month"}</strong></button>
          </div>
          <div className="month-picker-header"><strong>{year}</strong><div><button className="icon-button" type="button" aria-label="Previous year" disabled={year <= 2020} onClick={() => this.setState({ year: year - 1 })}><Icon name="left" /></button><button className="icon-button" type="button" aria-label="Next year" disabled={year >= 2026} onClick={() => this.setState({ year: year + 1 })}><Icon name="right" /></button></div></div>
          <div className="month-grid" role="group" aria-label="Select months">{MONTH_NAMES.map((name, i) => {
            const key = `${year}-${String(i + 1).padStart(2, "0")}`;
            const selected = draft.preset !== "lifetime" && !!draft.start && !!draft.end && key >= draft.start && key <= draft.end;
            return <button key={key} type="button" data-customer-month={key} className={`month-button ${selected ? "in-range" : ""} ${selected && (key === draft.start || key === draft.end) ? "is-endpoint" : ""} ${key === CURRENT_MONTH ? "is-current" : ""}`} aria-label={shortMonth(key)} aria-pressed={selected} disabled={key > CURRENT_MONTH} onClick={() => this.chooseMonth(key)}>{name}</button>;
          })}</div>
          <p className="month-picker-instructions" id="customer-date-instructions">{awaitingEnd ? "Choose an end month, or Apply to use just this month." : "Choose a month. Choose another to extend the range."}</p>
        </div>
      </div>
      <div className="date-scope-note"><Icon name="info" /><span>Module usage counts actions in the selected months. The current month is partial.</span></div>
      <div className="date-picker-footer"><span role="status">{draft.preset === "lifetime" ? "All available data" : rangeLabel(draft)}{draft.end === CURRENT_MONTH && draft.preset !== "lifetime" ? <span className="partial-period">Through 4 Oct 2026 · current month is partial</span> : null}</span><div><button className="ui-control" type="button" onClick={() => this.closeSurface()}>Cancel</button><button className="ui-control ui-primary" type="button" disabled={draft.preset !== "lifetime" && (!draft.start || !draft.end)} onClick={() => this.applyRange(draft)}>Apply</button></div></div>
    </div>;
  }
  private cells(totals: Totals) {
    return MODULES.map(({ key }) => <td className="numeric" key={key}>{totals[key] === null ? <span title={key === "gst" ? "GST is not available in the current dataset." : "Activity data is unavailable for this period."} aria-label="Not available">-</span> : number.format(totals[key]!)}</td>);
  }
  render() {
    const { filters, range, expanded, sort, direction, surface } = this.state;
    const rows = this.rows(), pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE)), page = Math.max(1, Math.min(pages, this.state.page)), start = (page - 1) * PAGE_SIZE;
    const visible = rows.slice(start, start + PAGE_SIZE), numbers = pageNumbers(page, pages);
    const filterCount = Number(filters.usage !== "all") + Number(filters.integration !== "all");
    return <div className="customer-shell">
      <header className="app-header"><div className="brand-left"><div className="brand"><span className="brand-mark"><Icon name="grid" /></span>AI Accountant</div><span className="brand-divider" /><span className="product-name">Product Metrics</span></div>
        <nav className="top-nav" aria-label="Product metrics navigation"><div className="dashboard-switcher">
          <button ref={node => { this.triggers.dashboard = node; }} type="button" id="customer-dashboard-trigger" className="dashboard-trigger ui-control" aria-expanded={surface === "dashboard"} aria-haspopup="menu" aria-controls="customer-dashboard-menu" onClick={() => this.showSurface("dashboard")} onKeyDown={e => { if (["ArrowDown", "ArrowUp"].includes(e.key) && surface !== "dashboard") { e.preventDefault(); this.showSurface("dashboard"); } }}><Icon name="grid" /><span>Customer</span><Icon name="down" /></button>
          <div ref={node => { this.panels.dashboard = node; }} hidden={surface !== "dashboard"} className="dashboard-menu ui-menu-surface" id="customer-dashboard-menu" role="menu" aria-label="Dashboards"><div className="menu-heading" role="presentation">Dashboards</div>{DASHBOARDS.map(item => <a key={item.name} href={item.href} role="menuitemradio" aria-checked={item.name === "Customer"} className={`dashboard-option ${item.name === "Customer" ? "is-current" : ""}`} onClick={e => { if (item.name === "Customer") { e.preventDefault(); this.closeSurface(); } }}><span className="menu-option-icon"><Icon name={item.icon} /></span><span className="menu-option-copy"><strong>{item.name}</strong><small>{item.description}</small></span>{item.name === "Customer" ? <Icon name="check" /> : null}</a>)}</div>
        </div><button ref={node => { this.helpTrigger = node; }} type="button" className="header-help" aria-label="Metric definitions" title="Metric definitions" onClick={() => { this.closeSurface(false); this.help?.showModal(); document.body.classList.add("modal-open"); }}><Icon name="help" /></button></nav>
      </header>
      <main className="customer-page" id="customer-main">
        <div className="page-heading"><h1>Customer</h1><div className="global-controls"><button className="reset-range" type="button" hidden={range.preset === "lifetime"} onClick={() => this.applyRange(LIFETIME)}>Reset</button><span className="global-control-label">Date range</span><button ref={node => { this.triggers.date = node; }} type="button" className="ui-control date-trigger" aria-label={`Date range: ${rangeLabel(range)}`} aria-haspopup="dialog" aria-expanded={surface === "date"} aria-controls="customer-date-panel" onClick={() => this.showSurface("date")}><Icon name="calendar" /><span>{rangeLabel(range)}</span><span className="chevron"><Icon name="down" /></span></button></div></div>
        <section className="customer-records po-record-layout" aria-label="Customer module usage">
          <div className="po-record-toolbar"><div className="po-record-tools">
            <div className="po-search"><Icon name="search" /><input ref={node => { this.search = node; }} type="search" value={filters.query} placeholder="Search customers or users" aria-label="Search customers or users" autoComplete="off" onChange={e => this.setFilter("query", e.currentTarget.value)} /><button type="button" hidden={!filters.query} aria-label="Clear customer search" onClick={() => { this.setFilter("query", ""); this.search?.focus(); }}><Icon name="close" /></button></div>
            <div className="po-filter-wrap"><button ref={node => { this.triggers.filters = node; }} type="button" className="ui-control" aria-expanded={surface === "filters"} aria-controls="customer-filters" onClick={() => this.showSurface("filters")}><Icon name="filter" /><span>Filters · {filterCount}</span></button>
              <div ref={node => { this.panels.filters = node; }} hidden={surface !== "filters"} className="po-filters" id="customer-filters"><div className="po-filter-head"><strong>Filter customers</strong><button type="button" onClick={() => this.resetFilters()}>Reset</button></div>{this.renderSelect("usage", "Module usage", [["all", "All customers"], ["active", "With usage"], ["inactive", "No usage"]])}{this.renderSelect("integration", "Integration", [["all", "All integrations"], ["Tally", "Tally"], ["Zoho Books", "Zoho Books"]])}<div className="po-filter-note">Filters select customers. Their totals and nested user contributions remain unchanged.</div></div>
            </div>
          </div></div>
          <div ref={node => { this.table = node; }} className="po-record-scroll" role="region" tabIndex={0} aria-label="Customer and user module usage, scroll for more columns">
            <table className="po-user-table customer-usage-table" aria-label="Customer module usage">
              <thead><tr><th scope="col"><span className="sr-only">Expand users</span></th>{[{ key: "name" as const, label: "Customer" }, ...MODULES].map(({ key, label }) => <th key={key} scope="col" className={key === "name" ? "" : "numeric"} aria-sort={sort === key ? direction === "asc" ? "ascending" : "descending" : undefined}><button type="button" onClick={() => this.sortBy(key)} disabled={key === "gst"} title={key === "gst" ? "GST activity is not available in the current dataset." : `Sort by ${label}`}>{label}{key !== "gst" ? <Icon name={sort === key ? direction === "asc" ? "up" : "down" : "sort"} /> : null}</button></th>)}</tr></thead>
              <tbody>{visible.length ? visible.flatMap(customer => {
                const open = expanded.has(customer.id);
                return [<tr key={customer.id} className={`po-user-row ${open ? "po-expanded" : ""}`} data-customer-id={customer.id}><td><button className="po-expander" type="button" aria-label={`${open ? "Collapse" : "Expand"} users for ${customer.name}`} aria-expanded={open} aria-controls={open ? `users-${customer.id}` : undefined} onClick={() => this.toggleRow(customer.id)}><Icon name={open ? "minus" : "plus"} /></button></td><td title={`${customer.name} · ${customer.id}`}>{customer.name}</td>{this.cells(customer.totals)}</tr>, open ? <tr key={`${customer.id}-users`} className="po-company-detail" id={`users-${customer.id}`}><td colSpan={7}><p className="po-company-caption">{number.format(customer.users.length)} {customer.users.length === 1 ? "user" : "users"} · {rangeLabel(range)}</p><table className="po-company-subtable customer-user-table" aria-label={`Users for ${customer.name}`}><thead><tr><th scope="col">User</th>{MODULES.map(module => <th key={module.key} scope="col">{module.label}</th>)}</tr></thead><tbody>{customer.users.map(user => <tr key={user.id}><td>{user.email}</td>{this.cells(user.totals)}</tr>)}</tbody></table></td></tr> : null];
              }) : <tr><td colSpan={7}><div className="po-empty"><strong>No customers match these filters</strong><span>Try a different customer or user name.</span><button type="button" onClick={() => this.resetFilters(true)}>Clear search and filters</button></div></td></tr>}</tbody>
            </table>
          </div>
          <footer className="po-record-foot"><span role="status">{rows.length ? `${start + 1}–${Math.min(start + PAGE_SIZE, rows.length)} of ${number.format(rows.length)} customers` : "0 matching customers"}</span><nav className="po-pagination" aria-label="Customer table pages"><button type="button" disabled={page === 1} aria-label="Previous page" onClick={() => this.goToPage(page - 1)}><Icon name="left" /></button>{numbers.flatMap((n, i) => [i > 0 && n - numbers[i - 1] > 1 ? <span className="page-ellipsis" key={`gap-${n}`} aria-hidden="true">…</span> : null, <button type="button" key={n} aria-label={`Page ${n}`} aria-current={page === n ? "page" : undefined} onClick={() => this.goToPage(n)}>{n}</button>])}<button type="button" disabled={page === pages} aria-label="Next page" onClick={() => this.goToPage(page + 1)}><Icon name="right" /></button></nav></footer>
        </section>
        <footer className="po-page-footer"><span>UI prototype · illustrative customer activity · GST unavailable</span><button type="button" onClick={() => { this.help?.showModal(); document.body.classList.add("modal-open"); }}>Data &amp; implementation notes</button></footer>
      </main>
      {this.renderDatePanel()}
      <div className="sr-only" role="status" aria-live="polite">{this.state.announcement}</div>
      <dialog ref={node => { this.help = node; }} className="info-dialog" aria-labelledby="customer-help-title" onClose={() => { document.body.classList.remove("modal-open"); }}><header className="dialog-header"><h2 className="dialog-title" id="customer-help-title">Customer module usage</h2><button className="close-button" type="button" aria-label="Close metric definitions" onClick={() => this.help?.close()}><Icon name="close" /></button></header><div className="info-body"><section className="definition-block"><h3>Activity counts</h3><p>Bills / AP and Invoices / AR sum their workflow events. Transactions includes statement uploads and transaction work, matching the overview module grouping. Sync counts accounting sync activity separately. These are actions, not unique documents.</p></section><section className="definition-block"><h3>Customers and users</h3><p>Each row is a stable company ID. Expanded users contribute to that customer only. Totals sum those contributions, even when a search matches just one user. The current fixture attributes each customer ID to one user; the table supports multiple users without inventing memberships. Equal customer names are not merged.</p></section><section className="definition-block"><h3>Unavailable is not zero</h3><p>GST is not in the source dataset, so it shows a dash. Zero means no recorded activity in an available period. Activity starts on {SOURCE_START}; earlier periods are unavailable. All values use the existing {SNAPSHOT_DATE} fixture snapshot, not live customer data.</p></section></div><div className="info-footnote">Same activity schedule as Product Overview. Replace the typed fixture adapter with reviewed customer and user activity records before using this page for decisions.</div></dialog>
    </div>;
  }
}
