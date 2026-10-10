"use client";

import React, { useEffect, useMemo, useState } from "react";
import type {
  CompanyInsightCategory,
  CompanyInsightSlice,
  CompaniesMonthlyInsights,
  ModuleBreakdownResponse,
  MonthModuleKey,
} from "../../lib/companies/types";

type View = "overview" | "breakdown" | "users" | "evidence";

interface Props {
  companyName: string;
  userLabel: string | null;
  month: string;
  module: MonthModuleKey;
  loading: boolean;
  breakdown: ModuleBreakdownResponse | null;
  onClose: () => void;
}

const nf = new Intl.NumberFormat("en-IN");
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TABS: Array<{ key: View; label: string }> = [
  { key: "overview", label: "Overview" },
  { key: "breakdown", label: "Event breakdown" },
  { key: "users", label: "Users" },
  { key: "evidence", label: "Event evidence" },
];

function safe(value: string | null | undefined): string | null {
  const text = value?.trim();
  if (!text) return null;
  return UUID.test(text) ? "Custom / internal value" : text.slice(0, 100);
}

function readable(value: string | null | undefined): string | null {
  const text = safe(value);
  if (!text) return null;
  const special: Record<string, string> = {
    gstr2b: "GSTR-2B",
    gst_reconciliation: "GST reconciliation",
    purchase_register: "Purchase register",
    invoice: "Invoice",
    bill: "Bill",
    statement: "Bank statement",
    bank: "Bank",
    receipt: "Receipt",
    payment: "Payment",
    contra: "Contra",
    stock_item: "Stock item",
    journal_voucher: "Journal voucher",
    newly_created: "New vendor created",
    existing_updated: "Existing vendor updated",
    bulk: "Bulk",
    single: "Single",
  };
  return special[text.toLowerCase()] ??
    text.replace(/[_-]/g, " ").replace(/\b\w/g, char => char.toUpperCase());
}

function fileLabel(value: string | null): string | null {
  const text = safe(value);
  if (!text) return null;
  const v = text.toLowerCase();
  if (v.includes("pdf")) return "PDF";
  if (v.includes("jpeg") || v.includes("jpg")) return "JPEG";
  if (v.includes("png")) return "PNG";
  if (v.includes("spreadsheetml") || v.includes("excel") || v === "xlsx") return "Excel";
  if (v.includes("csv")) return "CSV";
  return text;
}

function categoryLabel(key: CompanyInsightCategory, module: MonthModuleKey): string {
  switch (key) {
    case "status": return "Transaction status changes";
    case "ledger": return "Transaction ledger updates";
    case "type_change": return "Transaction type changes";
    case "upload":
      return module === "ap" ? "Bill uploads"
        : module === "ar" ? "Invoice uploads"
        : module === "gst" ? "Reconciliation uploads"
        : "Bank statement uploads";
    case "entity":
      return module === "ap" ? "Bills created"
        : module === "ar" ? "Invoices created" : "Entities created";
    case "vendor_mismatch": return "Vendor mismatch resolutions";
    case "reconciliation": return "Reconciliation processed";
    case "configuration": return "Transaction configuration";
    case "invoice_edit": return "Invoice bulk edits";
    default: return "Other recorded work";
  }
}

function sliceTitle(s: CompanyInsightSlice): string {
  switch (s.category) {
    case "status": return safe(s.action) ?? "Transaction status change";
    case "ledger": return readable(s.transaction_type) ?? "Ledger updated";
    case "type_change": return safe(s.action) ?? "Transaction type updated";
    case "upload": return (readable(s.type) ?? "File") + " upload";
    case "entity": return (readable(s.entity_type) ?? "Entity") + " created";
    case "vendor_mismatch": return readable(s.resolution_type) ?? "Vendor mismatch resolved";
    case "reconciliation": return "Reconciliation processed";
    case "configuration": return readable(s.type) ?? "Configuration edited";
    case "invoice_edit": return "Invoice bulk edited";
    default: return readable(s.event) ?? "Recorded event";
  }
}

function sliceDetail(s: CompanyInsightSlice): string {
  const bits: string[] = [];
  if (s.subtype) bits.push("Subtype: " + (readable(s.subtype) ?? "Other"));
  if (s.category !== "status" && s.category !== "type_change" && s.action) {
    bits.push("Action: " + (safe(s.action) ?? "Other"));
  }
  if (s.source) bits.push("Source: " + (safe(s.source) ?? "Other"));
  if (s.file_type) bits.push("File: " + (fileLabel(s.file_type) ?? "Other"));
  return bits.join(" · ") || "Source details not instrumented";
}

function timestamp(value: string | null | undefined): string {
  if (!value) return "Not available";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Not available";
  return date.toLocaleString("en-IN", {
    day: "numeric", month: "short", year: "numeric",
    hour: "numeric", minute: "2-digit", timeZone: "Asia/Kolkata",
  });
}

function monthLabel(value: string): string {
  const date = new Date(value.slice(0, 7) + "-01T12:00:00Z");
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("en-GB", { month: "short", year: "numeric", timeZone: "UTC" });
}

function itemText(items: number | null): string {
  return items === null ? "Not instrumented" : nf.format(items) + " reported items";
}

function eventCount(insights: CompaniesMonthlyInsights, category: string): number {
  return insights.categories.find(c => c.key === category)?.events ?? 0;
}

function SegmentBadge({ status }: { status: string | null }) {
  if (!status) return <span className="cid-muted">Not recorded</span>;
  const value = status.toLowerCase();
  const className = value === "success" || value === "accounting ready" ? "is-positive"
    : value === "failed" ? "is-negative"
    : value === "pending" ? "is-pending" : "";
  return <span className={"cid-status " + className}>{safe(status)}</span>;
}

export default function CompaniesInsightsDrill({
  companyName, userLabel, month, module, loading, breakdown, onClose,
}: Props) {
  const [view, setView] = useState<View>("overview");
  const [category, setCategory] = useState<string>("all");
  const insights = breakdown?.insights ?? null;

  useEffect(() => {
    setView("overview");
    setCategory("all");
  }, [month, module, companyName, userLabel]);

  const categories = insights?.categories ?? [];
  const slices = useMemo(() => insights?.slices ?? [], [insights]);
  const visibleCategories = category === "all"
    ? categories : categories.filter(item => item.key === category);
  const maxCategory = Math.max(1, ...categories.map(item => item.events));
  const maxDay = Math.max(1, ...(insights?.days.map(item => item.events) ?? []));
  const isUser = userLabel !== null;

  const jumpToCategory = (key: string) => {
    setCategory(key);
    setView("breakdown");
  };

  return (
    <div className="companies-breakdown-layout cid-layout">
      <header className="dialog-header cid-header">
        <div>
          <p className="dialog-eyebrow">Companies / {monthLabel(month)} / {module === "transactions" ? "Transactions" : module.toUpperCase()}</p>
          <h2 className="dialog-title" id="companies-breakdown-title">{companyName}</h2>
          <p className="dialog-subtitle">
            {isUser ? userLabel + " · User activity" : "Company activity breakdown"}
            {" · Recorded module work"}
          </p>
        </div>
        <button className="close-button" type="button" aria-label="Close activity breakdown" onClick={onClose}>
          <svg viewBox="0 0 24 24" aria-hidden="true" width="17" height="17">
            <path d="M5 5L19 19M19 5L5 19" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>
          </svg>
        </button>
      </header>
      <div className="cid-metrics" aria-label="Verified activity totals">
        <div className="cid-metric"><span>Recorded events</span><strong>{loading ? "…" : insights ? nf.format(insights.total) : "—"}</strong><small>{monthLabel(month)}</small></div>
        <div className="cid-metric"><span>Reported affected items</span><strong>{loading ? "…" : insights?.item_total != null ? nf.format(insights.item_total) : "—"}</strong><small>{insights?.instrumented_events ? "Instrumented events only" : "Not instrumented"}</small></div>
        <div className="cid-metric"><span>Active users</span><strong>{loading ? "…" : insights ? nf.format(insights.active_users) : "—"}</strong><small>Distinct tracked users</small></div>
        <div className="cid-metric"><span>Active days</span><strong>{loading ? "…" : insights ? nf.format(insights.active_days) : "—"}</strong><small>IST calendar days</small></div>
      </div>
      <div className="cid-tabs" role="tablist" aria-label="Company module activity views">
        {TABS.map(tab => (
          <button key={tab.key} type="button" role="tab"
            aria-selected={view === tab.key} className={"cid-tab " + (view === tab.key ? "is-active" : "")}
            onClick={() => setView(tab.key)}>{tab.label}</button>
        ))}
      </div>
      <div className="cid-body">
        {loading ? (
          <div className="cid-state" role="status">Loading verified {module.toUpperCase()} activity…</div>
        ) : !insights || !breakdown ? (
          <div className="cid-state" role="alert">
            <strong>Activity unavailable</strong>
            <span>The activity breakdown could not be verified. No substitute data is shown.</span>
          </div>
        ) : view === "overview" ? (
          <div className="cid-overview">
            <section className="cid-panel">
              <h3>Where activity happened</h3>
              <p className="cid-muted">{nf.format(insights.total)} recorded events, grouped by workflow</p>
              {categories.length ? (
                <>
                  <div className="cid-composition" role="img" aria-label="Activity share by event category">
                    {categories.map((item, index) => (
                      <span key={item.key} style={{ width: (item.events / Math.max(1, insights.total) * 100) + "%", background: "var(--cid-color-" + (index % 7) + ")" }} title={categoryLabel(item.key, module) + ": " + item.events + " events"} />
                    ))}
                  </div>
                  <div className="cid-category-list">
                    {categories.map((item, index) => (
                      <button key={item.key} type="button" className="cid-category-row" onClick={() => jumpToCategory(item.key)}>
                        <span className="cid-category-name">
                          <span className="cid-dot" style={{ background: "var(--cid-color-" + (index % 7) + ")" }} />
                          <span><strong>{categoryLabel(item.key, module)}</strong>
                            <small>{Math.round(item.events / Math.max(1, insights.total) * 1000) / 10}% of recorded events</small></span>
                        </span>
                        <span className="cid-category-count">{nf.format(item.events)} <span aria-hidden="true">›</span></span>
                      </button>
                    ))}
                  </div>
                </>
              ) : <p className="cid-empty">No eligible recorded work for this module and month.</p>}
            </section>
            <section className="cid-panel">
              <h3>Activity over time</h3>
              <p className="cid-muted">Event activity by Asia/Kolkata date</p>
              {insights.days.length ? (
                <div className="cid-chart" role="img" aria-label="Daily recorded event volumes">
                  {insights.days.map(day => (
                    <div className="cid-day" key={day.date} title={day.date + ": " + day.events + " events"}>
                      <strong>{nf.format(day.events)}</strong>
                      <div className="cid-day-bar" style={{ height: Math.max(8, (day.events / maxDay) * 84) + "px" }} />
                      <span>{day.date.slice(8, 10)}</span>
                    </div>
                  ))}
                </div>
              ) : <p className="cid-empty">No recorded activity days.</p>}
              <div className="cid-separator" />
              <h4>Interaction source</h4>
              <div className="cid-source-list">
                {insights.sources.slice(0, 5).map(src => (
                  <div className="cid-source-row" key={src.source}>
                    <span>{safe(src.source)}</span><strong>{nf.format(src.events)}</strong>
                  </div>
                ))}
                {insights.sources.length > 5 ? <small className="cid-muted">Other sources are included in event evidence.</small> : null}
              </div>
              <p className="cid-hint">
                {insights.first_at ? "First: " + timestamp(insights.first_at) : "No first event"}
                {" · "}
                {insights.last_at ? "Last: " + timestamp(insights.last_at) : "No last event"}
              </p>
            </section>
          </div>
        ) : view === "breakdown" ? (
          <section aria-label="Event breakdown">
            <h3 className="cid-section-title">Activity by event and subtype</h3>
            <p className="cid-muted">Expand a workflow to see actual actions, source, file type, and outcome.</p>
            <div className="cid-filters" aria-label="Filter event categories">
              <button type="button" className={category === "all" ? "is-active" : ""} onClick={() => setCategory("all")}>All · {nf.format(insights.total)}</button>
              {categories.map(item => (
                <button type="button" key={item.key} className={category === item.key ? "is-active" : ""}
                  onClick={() => setCategory(item.key)}>{categoryLabel(item.key, module)} · {nf.format(item.events)}</button>
              ))}
            </div>
            {!visibleCategories.length ? <p className="cid-empty">No events match this category.</p> : null}
            {visibleCategories.map((item, index) => (
              <details className="cid-group" key={item.key + ":" + category}
                defaultOpen={category !== "all" || index === 0}>
                <summary>
                  <span><strong>{categoryLabel(item.key, module)}</strong><small>{nf.format(item.events)} recorded events · {itemText(item.instrumented ? item.items : null)}</small></span>
                  <span className="cid-group-count">{nf.format(item.events)} <span aria-hidden="true">⌄</span></span>
                </summary>
                <div className="cid-slices">
                  {slices.filter(s => s.category === item.key).map((s, sliceIndex) => (
                    <div className="cid-slice" key={sliceIndex}>
                      <div>
                        <strong>{sliceTitle(s)}</strong>
                        <small>{sliceDetail(s)}</small>
                        <small>{s.instrumented ? itemText(s.items) : "Item count not instrumented"}</small>
                      </div>
                      <span className="cid-slice-right"><SegmentBadge status={s.status} /><strong>{nf.format(s.events)}</strong></span>
                    </div>
                  ))}
                </div>
              </details>
            ))}
            <p className="cid-hint">Each recorded event belongs to one group. Counts represent events, not necessarily unique transactions. Failed attempts and automatic Accounting Sync are excluded from core module usage.</p>
          </section>
        ) : view === "users" ? (
          <section aria-label="User activity">
            <h3 className="cid-section-title">People behind the activity</h3>
            <p className="cid-muted">{nf.format(insights.active_users)} tracked users · {nf.format(insights.unattributed_events)} unattributed events</p>
            {insights.users.length ? insights.users.map((user, index) => (
              <article className="cid-user" key={user.id}>
                <span className="cid-avatar" aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
                <div className="cid-user-main">
                  <strong>{user.id === "__unattributed__" ? "Unattributed activity" : (safe(user.label) ?? "Tracked user")}</strong>
                  <small className="cid-muted">Last active: {timestamp(user.last_at)}</small>
                  <div className="cid-user-numbers">
                    <span><strong>{nf.format(user.events)}</strong><small>Events</small></span>
                    <span><strong>{nf.format(user.active_days)}</strong><small>Active days</small></span>
                    {categories.filter(cat => (user.counts[cat.key] ?? 0) > 0).slice(0, 3).map(cat => (
                      <span key={cat.key}><strong>{nf.format(user.counts[cat.key] ?? 0)}</strong>
                        <small>{categoryLabel(cat.key, module)}</small></span>
                    ))}
                  </div>
                </div>
              </article>
            )) : <p className="cid-empty">No tracked user activity for this selection.</p>}
            {insights.user_groups_total > insights.users.length ?
              <p className="cid-hint">Showing the top {insights.users.length} user groups of {insights.user_groups_total}, ranked by event count.</p> : null}
          </section>
        ) : (
          <section aria-label="Grouped event evidence">
            <h3 className="cid-section-title">Recorded event evidence</h3>
            <p className="cid-muted">The event properties behind every grouped action. Item counts appear only where the product instrumented them.</p>
            <div className="cid-table-scroll" role="region" tabIndex={0} aria-label="Grouped event evidence table">
              <table className="cid-evidence">
                <thead><tr><th>Event</th><th>Subtype / action</th><th>Status</th><th className="cid-num">Events</th><th className="cid-num">Items</th><th>Last recorded</th></tr></thead>
                <tbody>
                  {slices.map((s, index) => (
                    <tr key={index}>
                      <td>{s.event}</td>
                      <td><strong>{sliceTitle(s)}</strong><small>{sliceDetail(s)}</small></td>
                      <td><SegmentBadge status={s.status}/></td>
                      <td className="cid-num">{nf.format(s.events)}</td>
                      <td className="cid-num">{s.instrumented ? nf.format(s.items ?? 0) : "—"}</td>
                      <td>{timestamp(s.latest_at)}</td>
                    </tr>
                  ))}
                  <tr className="cid-evidence-total"><td colSpan={3}>Total recorded</td><td className="cid-num">{nf.format(insights.total)}</td><td className="cid-num">{insights.item_total === null ? "—" : nf.format(insights.item_total)}</td><td />
                  </tr>
                </tbody>
              </table>
            </div>
            <details className="cid-technical">
              <summary>Technical details and original grouped subtypes</summary>
              <p className="cid-muted">Raw identifiers appear here only. They do not contribute extra events.</p>
              <div className="cid-table-scroll">
                <table className="cid-evidence">
                  <thead><tr><th>Original event</th><th>Raw subtype</th><th>Status</th><th className="cid-num">Events</th></tr></thead>
                  <tbody>{breakdown.rows.slice(0, 50).map((row, index) => (
                    <tr key={index}><td>{row.event}</td>
                      <td className="cid-raw">{row.subtype ?? "—"}</td>
                      <td>{row.status ?? "—"}</td>
                      <td className="cid-num">{nf.format(row.count)}</td></tr>
                  ))}</tbody>
                </table>
              </div>
              {breakdown.rows.length > 50 ? <p className="cid-muted">Showing 50 of {breakdown.rows.length} original grouped entries.</p> : null}
            </details>
            <p className="cid-hint">A dash under Items means the underlying event did not report item volume. It does not mean zero. Historical data reflects recorded telemetry.</p>
          </section>
        )}
      </div>
      <footer className="companies-breakdown-foot cid-footer">
        <span>{insights ? "Source through " + timestamp(insights.source_watermark_at) : monthLabel(month)}</span>
        <button type="button" onClick={() => setView("evidence")}>View source evidence →</button>
      </footer>
    </div>
  );
}
