/**
 * Engineering & Delivery preview shell.
 *
 * Deliberately data-free: this stage reproduces the existing Product Overview /
 * Retention 1560px, 12-column, 24px grid without publishing unverified Jira
 * numbers. Cards and section names follow the original GitLab delivery v1.
 * The future Jira data adapter can fill these surfaces without changing layout.
 */

type Metric = {
  label: string;
  explanation: string;
  period?: string;
};

const sprintMetrics: Metric[] = [
  {
    label: "Sprint commitments delivered",
    explanation: "Completed work against the sprint's original commitment",
    period: "Current sprint",
  },
  {
    label: "Work carried forward",
    explanation: "Committed issues not completed in the sprint",
    period: "Current sprint",
  },
  {
    label: "Mid-sprint additions",
    explanation: "Work introduced after the sprint started",
    period: "Current sprint",
  },
];

const attentionMetrics: Metric[] = [
  {
    label: "Stale work",
    explanation: "Open issues with no recent movement",
    period: "Current backlog",
  },
  {
    label: "Blocked issues",
    explanation: "Work that cannot progress without intervention",
    period: "Current backlog",
  },
  {
    label: "Open L1 bugs",
    explanation: "Highest-severity outstanding defects",
    period: "Current backlog",
  },
];

const qualityMetrics: Metric[] = [
  {
    label: "Open bug backlog",
    explanation: "Unresolved bugs across the engineering programme",
    period: "Current backlog",
  },
  {
    label: "Reopen rate",
    explanation: "Completed issues subsequently reopened",
    period: "Completed sprints",
  },
  {
    label: "QA rejection",
    explanation: "Items rejected after entering QA",
    period: "Completed sprints",
  },
];

function KpiShell({ label, explanation, period }: Metric) {
  return (
    <article className="metric-card ed-kpi-card" aria-label={label + ": data not connected"}>
      <div className="metric-label">{label}</div>
      <div className="metric-value ed-kpi-value" aria-hidden="true">—</div>
      <p className="metric-note">{explanation}</p>
      <span className="metric-period">{period}</span>
    </article>
  );
}

function SectionHeading({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div className="metrics-section-kicker">
      <span>{title}</span>
      <span className="metrics-section-description">{description}</span>
    </div>
  );
}

function ReportShell({
  title,
  description,
  columns,
  variant = "table",
  span = 6,
}: {
  title: string;
  description: string;
  columns?: string[];
  variant?: "table" | "bars" | "stages";
  span?: 6 | 12;
}) {
  return (
    <article
      className={"report-card ed-report-card " + (span === 12 ? "ed-report-wide" : "")}
      aria-label={title + ": layout preview; live Jira data not connected"}
    >
      <div className="report-header ed-report-header">
        <div>
          <h2>{title}</h2>
          <p className="report-subtitle">{description}</p>
        </div>
        <span className="ed-report-tag">Awaiting data</span>
      </div>
      <div className="ed-report-content">
        {variant === "table" ? (
          <div className="ed-placeholder-table" role="presentation">
            <div className="ed-table-head">
              {(columns ?? ["Measure", "Current sprint", "Previous sprint", "Change"]).map(column => (
                <span key={column}>{column}</span>
              ))}
            </div>
            {Array.from({ length: 4 }, (_, index) => (
              <div className="ed-placeholder-row" key={index} aria-hidden="true">
                {(columns ?? ["Measure", "Current sprint", "Previous sprint", "Change"]).map((column, i) => (
                  <span key={column} className={"ed-skeleton-line ed-skeleton-" + (i % 3)} />
                ))}
              </div>
            ))}
          </div>
        ) : variant === "bars" ? (
          <div className="ed-placeholder-bars" aria-hidden="true">
            {Array.from({ length: 5 }, (_, index) => (
              <div className="ed-placeholder-bar-row" key={index}>
                <span className="ed-skeleton-line ed-skeleton-label" />
                <span className="ed-placeholder-track"><i /></span>
                <span className="ed-skeleton-line ed-skeleton-number" />
              </div>
            ))}
          </div>
        ) : (
          <div className="ed-placeholder-stages" aria-hidden="true">
            {["To do", "In progress", "Code review", "QA"].map(label => (
              <div className="ed-placeholder-stage" key={label}>
                <span>{label}</span>
                <span className="ed-skeleton-line" />
              </div>
            ))}
          </div>
        )}
        <div className="ed-not-connected">
          <span className="ed-not-connected-icon" aria-hidden="true">◌</span>
          <div>
            <strong>Data connection pending</strong>
            <p>The Jira-backed metric and drill will be connected after the shell is approved.</p>
          </div>
        </div>
      </div>
      <footer className="report-footer ed-report-footer">
        <span>Layout preview · No values published</span>
        <span>Engineering &amp; Delivery</span>
      </footer>
    </article>
  );
}

function ReportGrid({ children }: { children: React.ReactNode }) {
  return <div className="ed-report-grid">{children}</div>;
}

export default function EngineeringDeliveryShell() {
  return (
    <main className="rd-page ed-page">
      <div className="rd-page-head ed-page-head">
        <div>
          <h1>Engineering &amp; Delivery</h1>
          <p>Sprint commitments, delivery flow, attention and quality</p>
        </div>
        <div className="ed-page-controls" aria-label="Future delivery reporting controls">
          <span className="ed-preview-indicator"><span aria-hidden="true" /> Preview shell</span>
          <button type="button" disabled className="static-control ed-filter-placeholder" title="Filters will be enabled after Jira data integration">
            Sprint: All <span aria-hidden="true">⌄</span>
          </button>
          <button type="button" disabled className="static-control ed-filter-placeholder" title="Filters will be enabled after Jira data integration">
            Filters <span aria-hidden="true">⌄</span>
          </button>
        </div>
      </div>

      <section className="kpi-grid po-kpis rd-kpi-grid ed-kpi-grid" aria-label="Sprint delivery key metrics">
        {sprintMetrics.map(metric => <KpiShell key={metric.label} {...metric} />)}
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Sprint delivery">
        <SectionHeading title="Sprint delivery" description="Did we finish the work we planned?" />
        <ReportGrid>
          <ReportShell title="Sprint commitment" description="Committed · delivered · carried forward"
            columns={["Measure", "Planned", "Delivered", "Remaining"]} />
          <ReportShell title="Sprint throughput" description="Completed engineering work by sprint"
            variant="bars" />
        </ReportGrid>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Attention analysis">
        <SectionHeading title="Attention" description="Work that needs action now" />
        <div className="kpi-grid po-kpis ed-inline-kpis">
          {attentionMetrics.map(metric => <KpiShell key={metric.label} {...metric} />)}
        </div>
        <ReportGrid>
          <ReportShell title="Work in flight" description="Open work by current status"
            variant="stages" span={12} />
        </ReportGrid>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Delivery analysis">
        <SectionHeading title="Delivery" description="Sprint-to-sprint reliability" />
        <ReportGrid>
          <ReportShell title="Planned versus done" description="Delivered work compared with each sprint's original plan"
            columns={["Measure", "Sprint −3", "Sprint −2", "Latest"]} />
          <ReportShell title="Issue types by sprint" description="Story, task, bug and other direct sprint work"
            columns={["Type", "Sprint −3", "Sprint −2", "Latest"]} />
        </ReportGrid>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Flow analysis">
        <SectionHeading title="Flow" description="Where work waits, and for how long" />
        <ReportGrid>
          <ReportShell title="Flow health" description="Time spent in each stage of the engineering lifecycle"
            variant="stages" />
          <ReportShell title="Engineering cycle time" description="Time from work started to work finished"
            variant="bars" />
        </ReportGrid>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Quality analysis">
        <SectionHeading title="Quality" description="Defect stock, engineering quality and review speed" />
        <div className="kpi-grid po-kpis ed-inline-kpis">
          {qualityMetrics.map(metric => <KpiShell key={metric.label} {...metric} />)}
        </div>
        <ReportGrid>
          <ReportShell title="Bug resolution" description="Age and time to resolve reported defects"
            variant="bars" />
          <ReportShell title="QA turnaround & code review" description="Elapsed time in QA and review stages"
            variant="stages" />
        </ReportGrid>
      </section>
    </main>
  );
}
