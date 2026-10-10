/**
 * Engineering & Delivery visual reference preview.
 *
 * The Product Metrics shared 1560px / 12-column / 24px grid owns page layout.
 * This reference uses the figures in the user's submitted original dashboard
 * screenshot. They are NOT presented as live or audited Jira data.
 *
 * Sections and drill labels follow the user's GitLab delivery implementation.
 * The real data adapter and authenticated drill-downs will be added separately.
 */

type Metric = {
  label: string;
  value: string;
  unit?: string;
  caption: string;
  evidence: string;
  period?: string;
  highlighted?: boolean;
  attention?: boolean;
};

type Section = {
  title: string;
  question: string;
};

const sprintMetrics: Metric[] = [
  {
    label: "Active sprint · SPEND Sprint 50",
    value: "41.9%",
    caption: "321 of 767 committed work delivered",
    evidence: "Delivered cohort: 305 · drill pending",
    highlighted: true,
    period: "Sprint commitment",
    attention: true,
  },
  {
    label: "Committed work not delivered",
    value: "468",
    unit: "issues",
    caption: "Committed by the sprint cutoff and still incomplete",
    evidence: "Not-delivered cohort: 468 · drill pending",
    period: "Sprint 50",
  },
  {
    label: "Mid-sprint additions",
    value: "209",
    unit: "issues",
    caption: "Scope added after sprint start",
    evidence: "Added cohort: 209 · drill pending",
    period: "Sprint 50",
  },
  {
    label: "Throughput",
    value: "214",
    unit: "completed",
    caption: "105 late-added completions",
    evidence: "Completed cohort: 214 · drill pending",
    period: "Sprint 50",
  },
];

const attentionMetrics: Metric[] = [
  {
    label: "Stale work",
    value: "750",
    unit: "issues",
    caption: "Open · untouched for 7+ days",
    evidence: "Stale cohort: 750 · drill pending",
  },
  {
    label: "Stale and blocked",
    value: "42",
    unit: "issues",
    caption: "Blocked and untouched",
    evidence: "Stale + blocked cohort: 42 · drill pending",
  },
  {
    label: "Open L1 bugs",
    value: "19",
    unit: "bugs",
    caption: "Open board-level L1",
    evidence: "Open L1 cohort: 19 · drill pending",
  },
  {
    label: "QA queue",
    value: "107",
    unit: "open",
    caption: "Awaiting a UAT exit decision",
    evidence: "QA queue: 107 · drill pending",
  },
  {
    label: "Blocked",
    value: "47",
    unit: "issues",
    caption: "5.3% of open work",
    evidence: "Blocked cohort: 47 · drill pending",
    attention: true,
  },
];

const qualityMetrics: Metric[] = [
  {
    label: "Open bug backlog",
    value: "326",
    unit: "open bugs",
    caption: "Median age 36.1d",
    evidence: "Open bugs: 326 · drill pending",
    highlighted: true,
  },
  {
    label: "Reopen rate",
    value: "8.8%",
    caption: "Returns to active work · Oct '26",
    evidence: "Reopened: 11 · drill pending",
  },
  {
    label: "QA rejection",
    value: "9.46%",
    caption: "UAT decisions rejected · all time",
    evidence: "Rejected: 342 · drill pending",
  },
  {
    label: "Bug resolution",
    value: "6.77d",
    caption: "Median · created to first Done",
    evidence: "Resolved: 3,104 · drill pending",
  },
  {
    label: "QA turnaround",
    value: "3d",
    caption: "Median UAT dwell before decision",
    evidence: "Decided stays: 2,724 · drill pending",
  },
  {
    label: "Code review",
    value: "4.2h",
    caption: "Median active-sprint dwell · SPEND Sprint 50",
    evidence: "Code review stays: 174 · drill pending",
  },
];

const wipRows = [
  { status: "To Do", count: "610", percent: 71.8, signal: "Queue" },
  { status: "UAT", count: "94", percent: 11.1, signal: "Waiting" },
  { status: "In Progress", count: "73", percent: 8.6, signal: "Active" },
  { status: "Blocked / On hold", count: "45", percent: 5.3, signal: "Attention", alert: true },
  { status: "Reopen", count: "10", percent: 1.2, signal: "Rework" },
  { status: "Code Review", count: "10", percent: 1.2, signal: "Review" },
  { status: "Staging", count: "8", percent: 0.9, signal: "Release" },
];

const sprintColumns = ["Sprint 50", "Sprint 49", "Sprint 48", "Sprint 46"];
const deliveryRows = [
  { name: "Committed work finished", values: ["41.9%", "47.1%", "49.7%", "31.3%"], important: true },
  { name: "Committed / delivered", values: ["321 / 767", "331 / 703", "318 / 640", "146 / 467"] },
  { name: "Carry to next", values: ["0", "422", "414", "417"] },
  { name: "Scope now", values: ["1,003", "976", "864", "621"] },
  { name: "Throughput", values: ["241", "231", "200", "19"] },
  { name: "Late-added completions", values: ["105", "128", "83", "14"] },
  { name: "Window", values: ["21 Sep–09 Oct '26", "07 Sep–19 Sep '26", "24 Aug–05 Sep '26", "Historical window"] },
];

const issueTypeColumns = ["Bug", "Epic", "Feature", "Improvement", "Story", "Task"];
const issueTypeRows = [
  { sprint: "Sprint 50", counts: ["579", "18", "7", "253", "19", "127"] },
  { sprint: "Sprint 49", counts: ["564", "17", "4", "234", "33", "124"] },
  { sprint: "Sprint 48", counts: ["462", "17", "3", "233", "29", "120"] },
  { sprint: "Sprint 46", counts: ["295", "17", "3", "209", "20", "77"] },
];

const dwellRows = [
  { name: "Blocked / On hold", value: "60.3d", hours: 60.3 * 24, attention: true },
  { name: "To Do", value: "9.3d", hours: 9.3 * 24 },
  { name: "UAT", value: "5d", hours: 5 * 24 },
  { name: "Reopen", value: "2.2d", hours: 2.2 * 24 },
  { name: "In Progress", value: "1.3d", hours: 1.3 * 24 },
  { name: "Code Review", value: "4.2h", hours: 4.2 },
  { name: "Staging", value: "3.5h", hours: 3.5 },
];

function MetricTile({ metric }: { metric: Metric }) {
  return (
    <article
      className={"metric-card ed-metric" + (metric.highlighted ? " ed-metric-featured" : "")}
      aria-label={metric.label + ": " + metric.value + " in the supplied reference screenshot, not live data"}
    >
      <div className="ed-metric-label">{metric.label}</div>
      <div className="ed-metric-readout">
        <strong>{metric.value}</strong>
        {metric.unit ? <span>{metric.unit}</span> : null}
      </div>
      <p className={"ed-metric-caption" + (metric.attention ? " ed-metric-caption-attention" : "")}>
        {metric.caption}
      </p>
      <div className="ed-metric-bottom">
        <span>{metric.evidence}</span>
      </div>
    </article>
  );
}

function SectionHead({ title, question }: Section) {
  return (
    <div className="metrics-section-kicker ed-section-heading">
      <span>{title}</span>
      <span className="metrics-section-description">{question}</span>
    </div>
  );
}

function Surface({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
}) {
  return (
    <article className="report-card ed-report">
      <div className="report-header ed-report-heading">
        <div>
          <h2>{title}</h2>
          <p className="report-subtitle">{subtitle}</p>
        </div>
      </div>
      {children}
    </article>
  );
}

function SprintFilters() {
  return (
    <div className="ed-filters" aria-label="Reference filter controls, inactive until Jira data is connected">
      {["Sprint", "Module", "Sub Module", "Severity", "Assignee"].map(label => (
        <span key={label} className="ed-filter-static" title="Preview only. The live filter is not connected.">
          {label}
          <svg viewBox="0 0 16 16" aria-hidden="true" width="13" height="13">
            <path d="m4 6 4 4 4-4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
          </svg>
        </span>
      ))}
    </div>
  );
}

function WorkInFlight() {
  return (
    <Surface title="Work in flight" subtitle="853 open issues by current status in the supplied reference">
      <div className="ed-table-shell ed-table-grow" role="region" aria-label="Work in flight status breakdown">
        <table className="ed-report-table ed-status-table">
          <thead>
            <tr><th>Status</th><th>Open issues</th><th>Share of queue</th><th>Signal</th></tr>
          </thead>
          <tbody>{wipRows.map(row => (
            <tr key={row.status} className={row.alert ? "ed-row-attention" : ""}>
              <th scope="row">{row.status}</th>
              <td>{row.count}</td>
              <td>
                <span className="ed-share">
                  <span className="ed-share-track" aria-hidden="true">
                    <span style={{ width: String(row.percent) + "%" }} />
                  </span>
                  <span>{row.percent.toFixed(1)}%</span>
                </span>
              </td>
              <td className={row.alert ? "ed-signal-alert" : ""}>{row.signal}</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      <p className="ed-table-meta">Listed statuses: 850 issues · Reference headline: 853 · Remaining 3 not broken down in the supplied screenshot.</p>
      <div className="ed-surface-foot">Open-work drill pending validated Jira integration</div>
    </Surface>
  );
}

function PlannedVsDone() {
  return (
    <Surface
      title="Planned versus done"
      subtitle="Active sprint and three previous sprints · Different windows; context, not a productivity trend"
    >
      <div className="ed-table-shell" role="region" tabIndex={0} aria-label="Sprint planning and throughput comparison">
        <table className="ed-report-table ed-compare">
          <thead>
            <tr>
              <th>Measure</th>
              {sprintColumns.map(name => <th key={name}>{name}</th>)}
            </tr>
          </thead>
          <tbody>{deliveryRows.map(row => (
            <tr key={row.name} className={row.important ? "ed-row-key" : ""}>
              <th scope="row">{row.name}</th>
              {row.values.map((value, index) => (
                <td key={index}>{value}</td>
              ))}
            </tr>
          ))}</tbody>
        </table>
      </div>
    </Surface>
  );
}

function IssueTypes() {
  return (
    <Surface title="Issue types by sprint" subtitle="Direct sprint items by issue type · Subtasks excluded">
      <div className="ed-table-shell" role="region" tabIndex={0} aria-label="Issue type counts by sprint">
        <table className="ed-report-table ed-issue-types">
          <thead>
            <tr><th>Sprint</th>{issueTypeColumns.map(column => <th key={column}>{column}</th>)}</tr>
          </thead>
          <tbody>{issueTypeRows.map(row => (
            <tr key={row.sprint}>
              <th scope="row">{row.sprint}</th>
              {row.counts.map((value, index) => <td key={index}>{value}</td>)}
            </tr>
          ))}</tbody>
        </table>
      </div>
    </Surface>
  );
}

function FlowHealth() {
  return (
    <Surface title="Flow health" subtitle="Active sprint stage dwell · SPEND Sprint 50">
      <div className="ed-flow-summary">
        <div>
          <span>Engineering cycle time</span>
          <div className="ed-flow-value">6.4<span>d</span></div>
          <p>Median time from first In Progress to Done</p>
        </div>
        <div className="ed-flow-measured">4,762 measured stays · drill pending</div>
      </div>
      <div className="ed-table-shell" role="region" aria-label="Median stage dwell time">
        <table className="ed-report-table ed-flow-table">
          <thead>
            <tr><th>Stage</th><th>Median dwell</th><th>Time</th></tr>
          </thead>
          <tbody>{dwellRows.map(row => (
            <tr key={row.name}>
              <th scope="row">{row.name}</th>
              <td>
                <span className="ed-flow-track" aria-hidden="true">
                  <span
                    className={row.attention ? "ed-flow-danger" : ""}
                    style={{width:String(Math.max(1,row.hours/(60.3*24)*100))+"%"}}
                  />
                </span>
              </td>
              <td>{row.value}</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
    </Surface>
  );
}

export default function EngineeringDeliveryShell() {
  return (
    <main className="rd-page ed-page">
      <div className="rd-page-head ed-page-head">
        <div className="ed-page-copy">
          <div className="ed-titleline">
            <h1>Engineering &amp; Delivery</h1>
            <span className="ed-reference-badge" title="Design reference, not a live Jira data connection">
              Reference snapshot · 9 Oct 2026
            </span>
          </div>
          <p>Sprint delivery, attention, flow and quality · Layout preview using the supplied reference</p>
        </div>
        <SprintFilters />
      </div>

      <section className="metrics-grid-section ed-section" aria-label="Sprint delivery">
        <SectionHead title="Sprint delivery" question="Did we finish the work we planned?" />
        <div className="ed-sprint-kpis">
          {sprintMetrics.map(metric => <MetricTile key={metric.label} metric={metric} />)}
        </div>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Attention">
        <SectionHead title="Attention" question="Work that needs action now" />
        <div className="ed-five-kpis">
          {attentionMetrics.map(metric => <MetricTile key={metric.label} metric={metric} />)}
        </div>
        <div className="ed-collection">
          <WorkInFlight />
        </div>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Delivery">
        <SectionHead title="Delivery" question="Did we finish the work we planned, sprint over sprint?" />
        <div className="ed-collection">
          <PlannedVsDone />
          <IssueTypes />
        </div>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Flow">
        <SectionHead title="Flow" question="Where does work wait, and how long does it take?" />
        <div className="ed-collection">
          <FlowHealth />
        </div>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Quality">
        <SectionHead title="Quality" question="How much is open, how old is it, and which way is it moving?" />
        <div className="ed-five-kpis">
          {qualityMetrics.map(metric => <MetricTile key={metric.label} metric={metric} />)}
        </div>
      </section>

      <footer className="ed-preview-note">
        <strong>Visual reference only.</strong> Values are transcribed from the supplied Engineering &amp; Delivery screenshot
        and have not been reconciled with the current Jira views. Filters and drills are noninteractive until the
        live data contract is implemented and audited.
      </footer>
    </main>
  );
}
