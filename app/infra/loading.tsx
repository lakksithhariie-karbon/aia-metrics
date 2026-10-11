import ProductMetricsHeader from "../../components/product-metrics-header";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "../delivery/delivery.css";
import "./infra.css";

export default function LoadingInfra() {
  return <div className="ed-shell infra-shell">
    <ProductMetricsHeader current="infra" />
    <main className="rd-page ed-page infra-page" role="status" aria-busy="true" aria-label="Loading infrastructure overview">
      <div className="rd-page-head ed-page-head"><div className="ed-page-copy">
        <h1>Infrastructure Overview</h1>
        <span className="ed-loading-subtitle ed-skeleton-line" aria-hidden="true" />
      </div></div>
      <section className="metrics-grid-section ed-section">
        <div className="metrics-section-kicker"><span>AWS cloud spending</span></div>
        <div className="ed-sprint-kpis ed-kpi-grid po-kpis" aria-hidden="true">
          {Array.from({ length: 4 }, (_, i) => <div className="ed-metric-wrap" key={i}>
            <div className="ed-loading-card"><div className="ed-skeleton-line" /><div className="ed-skeleton-line" /><div className="ed-skeleton-line" /></div>
          </div>)}
        </div>
      </section>
    </main>
  </div>;
}
