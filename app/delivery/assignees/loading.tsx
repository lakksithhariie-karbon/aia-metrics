import ProductMetricsHeader from "../../../components/product-metrics-header";
import "../delivery.css";
import "../../retention/retention.css";
import "../../customer/customer.css";
import "../../metrics-page-grid.css";
import "./assignees.css";

/* Loading placeholder mirrors the real matrix geometry: identity columns
   38/124/300, module columns flex-stretched, shared header/row heights —
   the page outline does not shift when the live table arrives. */
const MODULE_COUNT=9;
const BODY_ROWS=12;

export default function LoadingAssignees(){
  return <div className="companies-shell assignee-shell">
    <ProductMetricsHeader current="delivery" deliveryView="assignees"/>
    <main className="companies-page assignee-page" role="status" aria-busy="true"
      aria-label="Loading assignee workload matrix">
      <div className="page-heading companies-page-heading">
        <div className="companies-title-block"><h1>Assignee Overview</h1>
          <p>Open Jira work by assignee, module and issue type</p></div>
        <div className="global-controls assignee-current-scope">
          <span className="global-control-label">Reporting scope</span>
          <span className="ed-skeleton-line assignee-sk-chip" aria-hidden="true"/>
        </div>
      </div>
      <div className="metrics-section-kicker">
        <span>Assignee workload</span>
        <span className="metrics-section-description">Open work · Current issue state</span>
      </div>
      <section className="companies-records po-record-layout companies-monthly-records companies-grid-card">
        <div className="po-record-toolbar companies-command-bar">
          <div className="companies-toolbar-meta">
            <span className="ed-skeleton-line assignee-sk-meta-strong" aria-hidden="true"/>
            <span className="ed-skeleton-line assignee-sk-meta-sub" aria-hidden="true"/>
          </div>
          <div className="po-record-tools">
            <span className="ed-skeleton-line assignee-sk-tool assignee-sk-tool-info" aria-hidden="true"/>
            <span className="ed-skeleton-line assignee-sk-tool assignee-sk-tool-search" aria-hidden="true"/>
            <span className="ed-skeleton-line assignee-sk-tool assignee-sk-tool-filter" aria-hidden="true"/>
            <span className="ed-skeleton-line assignee-sk-tool assignee-sk-tool-columns" aria-hidden="true"/>
          </div>
        </div>
        <div className="po-record-scroll companies-monthly-scroll" role="presentation">
          <div className="assignee-sk-table" aria-hidden="true">
            <div className="assignee-sk-row assignee-sk-month-head">
              <span className="assignee-sk-cell assignee-sk-id1"/>
              <span className="assignee-sk-cell assignee-sk-id2"><span className="ed-skeleton-line assignee-sk-head-bar assignee-sk-head-left"/></span>
              <span className="assignee-sk-cell assignee-sk-id3"><span className="ed-skeleton-line assignee-sk-head-bar assignee-sk-head-left assignee-sk-head-wide"/></span>
              {Array.from({length:MODULE_COUNT},(_,i)=>
                <span key={i} className="assignee-sk-cell assignee-sk-module"><span className="ed-skeleton-line assignee-sk-head-bar"/></span>)}
            </div>
            <div className="assignee-sk-row assignee-sk-type-head">
              <span className="assignee-sk-cell assignee-sk-id1"/>
              <span className="assignee-sk-cell assignee-sk-id2"/>
              <span className="assignee-sk-cell assignee-sk-id3"/>
              {Array.from({length:MODULE_COUNT},(_,i)=>
                <span key={i} className="assignee-sk-cell assignee-sk-module"><span className="ed-skeleton-line assignee-sk-type-bar"/></span>)}
            </div>
            {Array.from({length:BODY_ROWS},(_,i)=>
              <div key={i} className="assignee-sk-row assignee-sk-body-row">
                <span className="assignee-sk-cell assignee-sk-id1"><span className="ed-skeleton-line assignee-sk-expander"/></span>
                <span className="assignee-sk-cell assignee-sk-id2"><span className="ed-skeleton-line assignee-sk-open"/></span>
                <span className="assignee-sk-cell assignee-sk-id3"><span className="ed-skeleton-line assignee-sk-name assignee-sk-name-varies"/></span>
                {Array.from({length:MODULE_COUNT},(_,j)=>
                  <span key={j} className="assignee-sk-cell assignee-sk-module"><span className="ed-skeleton-line assignee-sk-count"/></span>)}
              </div>)}
            <div className="assignee-sk-row assignee-sk-foot">
              <span className="assignee-sk-cell assignee-sk-id1"/>
              <span className="assignee-sk-cell assignee-sk-id2"><span className="ed-skeleton-line assignee-sk-foot-bar"/></span>
              <span className="assignee-sk-cell assignee-sk-id3"><span className="ed-skeleton-line assignee-sk-foot-bar assignee-sk-head-wide"/></span>
              {Array.from({length:MODULE_COUNT},(_,i)=>
                <span key={i} className="assignee-sk-cell assignee-sk-module"><span className="ed-skeleton-line assignee-sk-count"/></span>)}
            </div>
          </div>
        </div>
      </section>
    </main>
  </div>;
}