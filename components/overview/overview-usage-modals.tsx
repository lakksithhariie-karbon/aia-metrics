"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type {
  OverviewCoreModule,
  OverviewDrillCompanyDetail,
  OverviewDrillCompanyRow,
  OverviewDrillSegment,
  OverviewDrillUserRow,
  OverviewDrillUsersResponse,
  OverviewChartSegment,
} from "../../lib/overview/drill";

export type OverviewMetric = "wau" | "mau" | "stickiness";
const nf = new Intl.NumberFormat("en-US");
const PAGE_SIZE = 10;

function formatTime(value: string | null | undefined): string {
  if (!value) return "Not recorded";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "Not recorded";
  return d.toLocaleString("en-GB", {
    timeZone: "Asia/Kolkata",
    day: "numeric", month: "short", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  }) + " IST";
}
function formatDay(value: string | null | undefined): string {
  if (!value) return "Not recorded";
  const d = new Date(value.length === 10 ? value + "T12:00:00Z" : value);
  if (Number.isNaN(d.getTime())) return "Not recorded";
  return d.toLocaleDateString("en-GB", {
    timeZone: value.length === 10 ? "UTC" : "Asia/Kolkata",
    day: "numeric", month: "short", year: "numeric",
  });
}
function Icon({ name }: { name: "close" | "left" | "right" | "down" | "search" }) {
  const names = { close: "close", left: "left", right: "right", down: "down", search: "search" };
  return <svg className="rd-icon" aria-hidden="true"><use href={"#i-" + names[name]} /></svg>;
}

async function post<T>(body: Record<string, unknown>, signal: AbortSignal): Promise<T> {
  const response = await fetch("/api/overview-drill", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    cache: "no-store",
    body: JSON.stringify(body),
    signal,
  });
  if (!response.ok) {
    if (response.status === 409 || response.status === 404) {
      throw new Error("This snapshot changed. Refresh the dashboard to see the latest data.");
    }
    throw new Error("Live drill could not be loaded. Try again.");
  }
  return await response.json() as T;
}

function expectedTotal(snapshot: OverviewUsageSnapshot, segment: OverviewDrillSegment) {
  if (segment === "wau") return snapshot.wau.current;
  if (segment === "mau") return snapshot.mau.current;
  return snapshot.mau.current - snapshot.wau.current;
}
function segmentLabel(segment: OverviewDrillSegment) {
  if (segment === "wau") return "Weekly active";
  if (segment === "mau_only") return "MAU only";
  return "All monthly active";
}
function numberPages(page: number, total: number): Array<number | "ellipsis"> {
  const indexes = [...new Set([1, page - 1, page, page + 1, total])]
    .filter(value => value >= 1 && value <= total)
    .sort((a, b) => a - b);
  const items: Array<number | "ellipsis"> = [];
  for (let i = 0; i < indexes.length; i++) {
    if (i && indexes[i] - indexes[i - 1] > 1) items.push("ellipsis");
    items.push(indexes[i]);
  }
  return items;
}
function moduleLabel(key: "ap" | "ar" | "transactions") {
  return key === "ap" ? "AP / Bills" : key === "ar" ? "AR / Invoices" : "Transactions";
}
export function OverviewUsageModal({
  metric, snapshot, onClose, onDefinition,
}: {
  metric: OverviewMetric;
  snapshot: OverviewUsageSnapshot;
  onClose: () => void;
  onDefinition: (metric: OverviewMetric) => void;
}) {
  const initialSegment: OverviewDrillSegment = metric === "wau" ? "wau" : metric === "mau" ? "mau" : "wau";
  const [segment, setSegment] = useState<OverviewDrillSegment>(initialSegment);
  const [module, setModule] = useState<OverviewCoreModule>("all");
  const [query, setQuery] = useState("");
  const [deferredQuery, setDeferredQuery] = useState("");
  const [page, setPage] = useState(1);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [data, setData] = useState<OverviewDrillUsersResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [retry, setRetry] = useState(0);
  const [focus, setFocus] = useState<{
    userId: string; companyId: string; companyName: string; scope: "wau" | "mau";
  } | null>(null);
  const cache = useRef<Map<string, OverviewDrillUsersResponse>>(new Map());
  const scroll = useRef<HTMLDivElement>(null);
  const companyTrigger = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => setDeferredQuery(query), 250);
    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    setPage(1);
    setExpanded(new Set());
    scroll.current?.scrollTo({ top: 0 });
  }, [segment, module, deferredQuery]);

  const cacheKey = [
    snapshot.snapshotId, segment, module, deferredQuery, page,
  ].join("|");

  useEffect(() => {
    const controller = new AbortController();
    const cached = cache.current.get(cacheKey);
    if (cached) {
      setData(cached);
      setError(null);
      setLoading(false);
      return () => controller.abort();
    }
    setLoading(true);
    setError(null);
    setData(null);
    post<OverviewDrillUsersResponse>({
      action: "users", snapshot_id: snapshot.snapshotId, segment, module,
      query: deferredQuery, page, page_size: PAGE_SIZE,
    }, controller.signal).then(result => {
      if (controller.signal.aborted) return;
      if (result.snapshot_id !== snapshot.snapshotId ||
          result.segment_total !== expectedTotal(snapshot, segment)) {
        throw new Error("The user totals no longer match this snapshot. Refresh the dashboard.");
      }
      cache.current.set(cacheKey, result);
      setData(result);
    }).catch(err => {
      if (!controller.signal.aborted) setError(
        err instanceof Error ? err.message : "Could not load the drill.",
      );
    }).finally(() => {
      if (!controller.signal.aborted) setLoading(false);
    });
    return () => controller.abort();
  }, [cacheKey, deferredQuery, module, page, retry, segment, snapshot]);

  useEffect(() => {
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = oldOverflow; };
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      if (document.getElementById("po-live-kpi-dialog")?.hasAttribute("open")) return;
      event.preventDefault();
      if (focus) setFocus(null);
      else onClose();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [focus, onClose]);

  const tabs: Array<[OverviewDrillSegment, string]> =
    metric === "wau" ? [["wau", "All weekly active"]]
    : metric === "mau" ? [
      ["mau", "All MAU"], ["wau", "Also WAU"], ["mau_only", "MAU only"],
    ]
    : [["wau", "Weekly active"], ["mau_only", "MAU only"]];

  const title = metric === "wau" ? "Weekly core-active users"
    : metric === "mau" ? "Monthly core-active users" : "Stickiness";
  const totalPages = Math.max(1, Math.ceil((data?.total ?? 0) / PAGE_SIZE));
  const pageStart = data?.rows.length ? (page - 1) * PAGE_SIZE + 1 : 0;
  const pageEnd = data?.rows.length ? pageStart + data.rows.length - 1 : 0;
  const scope: "wau" | "mau" = segment === "wau" ? "wau" : "mau";

  function expand(id: string) {
    setExpanded(existing => existing.has(id) ? new Set() : new Set([id]));
  }
  function openCompany(user: OverviewDrillUserRow, company: OverviewDrillCompanyRow, button: HTMLButtonElement) {
    companyTrigger.current = button;
    setFocus({
      userId: user.id, companyId: company.id, companyName: company.name, scope,
    });
  }

  return (
    <>
      <div className="rd-overlay" role="presentation">
        <section
          className="rd-modal rd-activation-modal po-usage-modal"
          role="dialog" aria-modal="true" aria-labelledby="po-usage-title"
          id="po-usage-users-modal"
        >
          <header className="rd-modal-head">
            <div>
              <p>Product Overview · {segment === "wau" ? "Rolling 7 days" : "Rolling 30 days"}</p>
              <h2 id="po-usage-title">{title}</h2>
              <span>
                {nf.format(expectedTotal(snapshot, segment))} users ·{" "}
                {segmentLabel(segment)} · As of {formatTime(snapshot.asOf)}
              </span>
            </div>
            <button className="rd-close" type="button" onClick={onClose} aria-label="Close user drill">
              <Icon name="close" />
            </button>
          </header>

          <div className="po-usage-summary">
            <div><span>Weekly active</span><strong>{nf.format(snapshot.wau.current)}</strong></div>
            <div><span>Monthly active</span><strong>{nf.format(snapshot.mau.current)}</strong></div>
            <div><span>Stickiness</span><strong>
              {snapshot.mau.current
                ? (snapshot.wau.current * 100 / snapshot.mau.current).toFixed(1) + "%"
                : "—"}
            </strong></div>
            <button type="button" className="po-usage-definition" onClick={() => onDefinition(metric)}>
              <Icon name="right" /> Definition
            </button>
          </div>

          <div className="rd-drill-toolbar po-usage-toolbar">
            <div className="rd-status-tabs" aria-label="Usage segment">
              {tabs.map(([key, label]) => (
                <button
                  key={key} type="button" aria-pressed={segment === key}
                  onClick={() => setSegment(key)}
                >
                  {label}<span>{nf.format(expectedTotal(snapshot, key))}</span>
                </button>
              ))}
            </div>
            <div className="po-usage-filters">
              <label className="po-usage-select-label">
                <span className="sr-only">Module</span>
                <select
                  value={module} aria-label="Filter by module"
                  onChange={event => setModule(event.currentTarget.value as OverviewCoreModule)}
                >
                  <option value="all">All modules</option>
                  <option value="ap">AP / Bills</option>
                  <option value="ar">AR / Invoices</option>
                  <option value="transactions">Transactions</option>
                </select>
              </label>
              <div className="rd-search">
                <Icon name="search" />
                <input
                  value={query}
                  aria-label="Search users or companies"
                  onChange={event => setQuery(event.currentTarget.value)}
                  placeholder="Search users or companies"
                />
                {query ? (
                  <button type="button" onClick={() => setQuery("")} aria-label="Clear search">
                    <Icon name="close" />
                  </button>
                ) : null}
              </div>
            </div>
          </div>

          <div className="rd-table-wrap po-usage-table-wrap" ref={scroll}>
            {loading ? (
              <div className="rd-loading">Loading verified users and companies…</div>
            ) : error ? (
              <div className="rd-empty po-usage-error">
                <span>{error}</span>
                <button type="button" onClick={() => setRetry(n => n + 1)}>Try again</button>
              </div>
            ) : !data ? (
              <div className="rd-empty">No user data available.</div>
            ) : (
              <table className="rd-activation-table po-usage-table">
                <thead>
                  <tr>
                    <th scope="col"><span className="sr-only">Expand user</span></th>
                    <th scope="col">User / Company</th>
                    <th scope="col">Companies</th>
                    <th scope="col">Core actions</th>
                    <th scope="col">Active days</th>
                    <th scope="col">Last active</th>
                    <th scope="col">AP</th>
                    <th scope="col">AR</th>
                    <th scope="col">Transaction</th>
                  </tr>
                </thead>
                <tbody>
                  {data.rows.length ? data.rows.flatMap(user => {
                    const isExpanded = expanded.has(user.id);
                    const parent = (
                      <tr key={"user:" + user.id} className={isExpanded ? "is-expanded" : ""}>
                        <td>
                          <button className="rd-expander" type="button"
                            aria-expanded={isExpanded}
                            aria-label={(isExpanded ? "Collapse " : "Expand ") + user.email}
                            onClick={() => expand(user.id)}
                          >
                            <Icon name={isExpanded ? "down" : "right"} />
                          </button>
                        </td>
                        <td>
                          <button className="rd-company-link po-usage-user-link"
                            type="button" onClick={() => expand(user.id)}
                          >
                            <strong>{user.email}</strong>
                            <span>Distinct user · {nf.format(user.active_days)} active days</span>
                          </button>
                        </td>
                        <td><span className="po-usage-pill">{user.companies.length}</span></td>
                        <td className="has-value">{nf.format(user.actions)}</td>
                        <td>{nf.format(user.active_days)}</td>
                        <td>{formatTime(user.last_active_at)}</td>
                        <td>{nf.format(user.modules.ap)}</td>
                        <td>{nf.format(user.modules.ar)}</td>
                        <td>{nf.format(user.modules.transactions)}</td>
                      </tr>
                    );
                    if (!isExpanded) return [parent];
                    const nested = user.companies.map(company => (
                      <tr className="po-usage-company-row rd-user-row"
                        key={"company:" + user.id + ":" + company.id}
                      >
                        <td />
                        <td>
                          <span className="rd-user-indent">
                            <button type="button" className="po-usage-company-link"
                              onClick={event => openCompany(user, company, event.currentTarget)}
                              title="Open full company activity profile"
                            >
                              {company.name}
                              <small>View full company breakdown →</small>
                            </button>
                          </span>
                        </td>
                        <td>{company.is_test ? <span className="rd-status">Test</span> : "Company"}</td>
                        <td>{nf.format(company.actions)}</td>
                        <td>{nf.format(company.active_days)}</td>
                        <td>{formatTime(company.last_active_at)}</td>
                        <td>{nf.format(company.modules.ap)}</td>
                        <td>{nf.format(company.modules.ar)}</td>
                        <td>{nf.format(company.modules.transactions)}</td>
                      </tr>
                    ));
                    return [parent, ...nested];
                  }) : (
                    <tr><td colSpan={9}>
                      <div className="rd-empty">
                        No matching users. Change the search or module filter.
                      </div>
                    </td></tr>
                  )}
                </tbody>
              </table>
            )}
          </div>

          <footer className="rd-modal-foot rd-modal-foot-paginated">
            <div className="rd-table-summary">
              <span>Distinct users · Independent core work · Accounting Sync excluded</span>
              <small>
                {data
                  ? "Showing " + nf.format(pageStart) + "–" + nf.format(pageEnd) +
                    " of " + nf.format(data.total) + " matching users"
                  : "Pinned to published source snapshot #" + snapshot.snapshotId}
              </small>
            </div>
            {data && totalPages > 1 ? (
              <nav className="rd-pagination" aria-label="User drill pages">
                <button type="button" disabled={page <= 1}
                  aria-label="Previous page" onClick={() => setPage(n => n - 1)}>
                  <Icon name="left" />
                </button>
                {numberPages(page, totalPages).map((item, index) =>
                  item === "ellipsis" ? (
                    <span className="rd-page-ellipsis" key={"ellipsis:" + index}>…</span>
                  ) : (
                    <button type="button" key={item}
                      aria-current={page === item ? "page" : undefined}
                      onClick={() => setPage(item)}>{item}</button>
                  ),
                )}
                <button type="button" disabled={page >= totalPages}
                  aria-label="Next page" onClick={() => setPage(n => n + 1)}>
                  <Icon name="right" />
                </button>
              </nav>
            ) : null}
          </footer>
        </section>
      </div>
      {focus ? (
        <OverviewCompanyDetailModal
          focus={focus} snapshot={snapshot} onClose={() => {
            setFocus(null);
            requestAnimationFrame(() => companyTrigger.current?.focus({ preventScroll: true }));
          }}
        />
      ) : null}
    </>
  );
}

export type OverviewCompanyFocus = {
  userId: string;
  companyId: string;
  companyName: string;
} & (
  { scope: "wau" | "mau"; chartKey?: never; chartSegment?: never } |
  { scope: "weekly" | "frequency"; chartKey: string; chartSegment: OverviewChartSegment }
);

export function OverviewCompanyDetailModal({
  focus, snapshot, onClose,
}: {
  focus: OverviewCompanyFocus;
  snapshot: OverviewUsageSnapshot;
  onClose: () => void;
}) {
  const [data, setData] = useState<OverviewDrillCompanyDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<"overview" | "activity" | "users">("overview");
  const [retry, setRetry] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setData(null);
    setError(null);
    const chart = focus.scope === "weekly" || focus.scope === "frequency";
    post<OverviewDrillCompanyDetail>({
      action: chart ? "chart_company" : "company",
      snapshot_id: snapshot.snapshotId,
      ...(chart ? {
        kind: focus.scope,
        key: focus.chartKey,
        segment: focus.chartSegment,
      } : { scope: focus.scope }),
      user_id: focus.userId,
      company_id: focus.companyId,
    }, controller.signal).then(result => {
      if (!controller.signal.aborted) setData(result);
    }).catch(err => {
      if (!controller.signal.aborted) setError(
        err instanceof Error ? err.message : "Company detail is unavailable.",
      );
    }).finally(() => {
      if (!controller.signal.aborted) setLoading(false);
    });
    return () => controller.abort();
  }, [focus.companyId, focus.scope, focus.userId,
      focus.chartKey, focus.chartSegment, retry, snapshot.snapshotId]);

  const milestones = useMemo(() => {
    if (!data) return [];
    return [
      ["Company created", data.milestones.company_created_at],
      ["Integration success", data.milestones.integration_at],
      ["First core work", data.milestones.first_independent_activity_at],
      ["First sync", data.milestones.first_qualifying_sync_at],
      ["Latest sync", data.milestones.last_qualifying_sync_at],
    ];
  }, [data]);

  return (
    <div className="rd-overlay rd-overlay-level-2" role="presentation">
      <section className="rd-modal rd-company-modal po-company-modal"
        role="dialog" aria-modal="true" aria-labelledby="po-core-company-title">
        <header className="rd-company-head">
          <div className="rd-company-topline">
            <button className="rd-back" type="button" onClick={onClose}>
              <Icon name="left" /> Back to active users
            </button>
            <button className="rd-close" type="button" onClick={onClose}
              aria-label="Back to user list">
              <Icon name="close" />
            </button>
          </div>
          <div>
            <div>
              <p>Company activity profile · {focus.scope === "wau" ? "7 days" : focus.scope === "mau" ? "30 days" : focus.scope === "weekly" ? "Completed week" : "Four completed weeks"}</p>
              <h2 id="po-core-company-title">{data?.company.name ?? focus.companyName}</h2>
            </div>
            <div className="rd-company-tags">
              <span>{focus.scope === "wau" ? "Weekly active" : focus.scope === "mau" ? "Monthly active" : focus.scope === "weekly" ? "Weekly chart" : "Usage frequency"}</span>
              {data?.company.is_test ? <span>Test</span> : null}
              {data ? <span>{nf.format(data.stats.active_users)} active users</span> : null}
            </div>
          </div>
        </header>

        <div className="rd-company-scroll po-company-scroll">
          {loading ? <div className="rd-loading">Loading verified company activity…</div>
          : error || !data ? (
            <div className="rd-empty po-usage-error">
              <span>{error ?? "No company details found."}</span>
              <button type="button" onClick={() => setRetry(n => n + 1)}>Try again</button>
              <button type="button" onClick={onClose}>Back to users</button>
            </div>
          ) : (
            <>
              <div className="po-company-context">
                <strong>Reporting window</strong>
                <span>{formatTime(data.window.start)} to {formatTime(data.window.end)}</span>
                <small>Company-wide independent work, not just the selected user's actions</small>
              </div>

              <div className="rd-health-strip po-company-health">
                <div><span>Core actions</span><strong>{nf.format(data.stats.core_actions)}</strong></div>
                <div><span>Active users</span><strong>{nf.format(data.stats.active_users)}</strong></div>
                <div><span>Active days</span><strong>{nf.format(data.stats.active_days)}</strong></div>
                <div><span>Last core work</span><strong className="po-company-date">
                  {formatTime(data.stats.last_activity_at)}
                </strong></div>
              </div>

              <div className="rd-status-tabs po-company-tabs" aria-label="Company profile section">
                {([
                  ["overview", "Overview"], ["activity", "Activity"], ["users", "Users"],
                ] as const).map(([key, label]) => (
                  <button type="button" aria-pressed={tab === key} key={key}
                    onClick={() => setTab(key)}>{label}</button>
                ))}
              </div>

              {tab === "overview" ? (
                <>
                  <section className="rd-lifecycle-card">
                    <div className="rd-section-title">
                      <div>
                        <h3>Company lifecycle</h3>
                        <p>Recorded milestones, including separate sync history</p>
                      </div>
                    </div>
                    <div className="rd-timeline">
                      {milestones.map(([label, value], index) => (
                        <div className={"rd-milestone " + (!value ? "is-empty" : "")}
                          key={label}>
                          <span className="rd-dot" />
                          {index < milestones.length - 1 ? <i /> : null}
                          <small>{label}</small>
                          <strong title={formatTime(value)}>{formatDay(value)}</strong>
                        </div>
                      ))}
                    </div>
                  </section>
                  <div className="rd-detail-grid po-company-overview-grid">
                    <section className="rd-detail-card">
                      <div className="rd-section-title">
                        <div><h3>Core actions by module</h3>
                          <p>Independent work in this reporting window</p></div>
                      </div>
                      <div className="po-company-module-list">
                        {(["ap", "ar", "transactions"] as const).map(key => (
                          <div key={key}>
                            <span>{moduleLabel(key)}</span>
                            <div className="po-company-module-track" aria-hidden="true">
                              <i style={{
                                width: data.stats.core_actions
                                  ? data.stats.modules[key] / data.stats.core_actions * 100 + "%"
                                  : "0%",
                              }} />
                            </div>
                            <strong>{nf.format(data.stats.modules[key])}</strong>
                          </div>
                        ))}
                      </div>
                    </section>
                    <section className="rd-detail-card">
                      <div className="rd-section-title">
                        <div><h3>Activity context</h3>
                          <p>Measured only within the selected window</p></div>
                      </div>
                      <div className="po-company-context-list">
                        <div><span>First observed work</span><strong>
                          {formatTime(data.stats.first_activity_at)}
                        </strong></div>
                        <div><span>Last observed work</span><strong>
                          {formatTime(data.stats.last_activity_at)}
                        </strong></div>
                        <div><span>Observed users</span><strong>
                          {nf.format(data.stats.active_users)}
                        </strong></div>
                        <div><span>Selected user's contribution</span><strong>
                          {nf.format(
                            data.users.find(u => u.id === focus.userId)?.actions ?? 0,
                          )} actions
                        </strong></div>
                      </div>
                    </section>
                  </div>
                </>
              ) : null}

              {tab === "activity" ? (
                <>
                  <section className="rd-weeks-card po-company-week-card">
                    <div className="rd-section-title">
                      <div>
                        <h3>Weekly activity timeline</h3>
                        <p>Calendar weeks in IST. Partial weeks show observed events only.</p>
                      </div>
                    </div>
                    <div className="rd-weeks-wrap">
                      <table>
                        <thead><tr>
                          <th scope="col">Week starting</th><th scope="col">Users</th>
                          <th scope="col">Core actions</th><th scope="col">AP</th>
                          <th scope="col">AR</th><th scope="col">Transaction</th>
                        </tr></thead>
                        <tbody>
                          {data.weeks.map(week => (
                            <tr key={week.week_start}>
                              <td><strong>{formatDay(week.week_start)}</strong></td>
                              <td>{nf.format(week.active_users)}</td>
                              <td>{nf.format(week.actions)}</td>
                              <td>{nf.format(week.modules.ap)}</td>
                              <td>{nf.format(week.modules.ar)}</td>
                              <td>{nf.format(week.modules.transactions)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </section>
                  <section className="rd-weeks-card po-company-week-card">
                    <div className="rd-section-title">
                      <div>
                        <h3>Recent independent core activity</h3>
                        <p>Latest 30 observed actions in the reporting window</p>
                      </div>
                    </div>
                    <div className="rd-weeks-wrap po-company-evidence">
                      <table>
                        <thead><tr>
                          <th scope="col">When</th><th scope="col">Event</th>
                          <th scope="col">Module</th><th scope="col">User</th>
                        </tr></thead>
                        <tbody>
                          {data.recent_events.map((event, index) => (
                            <tr key={event.at + ":" + index}>
                              <td>{formatTime(event.at)}</td>
                              <td>{event.event}</td>
                              <td>{moduleLabel(event.module)}</td>
                              <td className={event.user_id === focus.userId ? "po-focus-user" : ""}>
                                {event.user_email}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </section>
                </>
              ) : null}

              {tab === "users" ? (
                <section className="rd-weeks-card po-company-week-card">
                  <div className="rd-section-title">
                    <div>
                      <h3>Active users in this company</h3>
                      <p>Each user counts once; highlighted user opened this company</p>
                    </div>
                  </div>
                  <div className="rd-weeks-wrap po-company-member-table">
                    <table>
                      <thead><tr>
                        <th scope="col">User</th><th scope="col">Core actions</th>
                        <th scope="col">Active days</th><th scope="col">AP</th>
                        <th scope="col">AR</th><th scope="col">Transaction</th>
                        <th scope="col">Last active</th>
                      </tr></thead>
                      <tbody>{data.users.map(user => (
                        <tr key={user.id} className={user.id === focus.userId ? "po-focused-row" : ""}>
                          <td><strong>{user.email}</strong>
                            {user.id === focus.userId ? <small>Selected user</small> : null}
                          </td>
                          <td>{nf.format(user.actions)}</td>
                          <td>{nf.format(user.active_days)}</td>
                          <td>{nf.format(user.modules.ap)}</td>
                          <td>{nf.format(user.modules.ar)}</td>
                          <td>{nf.format(user.modules.transactions)}</td>
                          <td>{formatTime(user.last_active_at)}</td>
                        </tr>
                      ))}</tbody>
                    </table>
                  </div>
                </section>
              ) : null}

              <p className="po-company-freshness">
                Snapshot #{data.snapshot_id} · Source watermark {formatTime(data.source_watermark_at)}
                {" · "}Sync events are reported in lifecycle milestones but never count as independent core work.
              </p>
            </>
          )}
        </div>
      </section>
    </div>
  );
}
