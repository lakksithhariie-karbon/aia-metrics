import ProductMetricsHeader from "../../components/product-metrics-header";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "../delivery/delivery.css";
import "./infra.css";

export default function LoadingInfra() {
  return <div className="ed-shell infra-shell">
    <ProductMetricsHeader current="infra"/>
    <main className="rd-page ed-page infra-page" role="status" aria-busy="true"
      aria-label="Loading infrastructure overview">
      <div className="rd-page-head ed-page-head"><div className="ed-page-copy">
        <h1>Infrastructure Overview</h1>
        <span className="ed-loading-subtitle ed-skeleton-line" aria-hidden="true"/>
      </div></div>
      {["AWS cloud spending","Data confidence"].map(section=>
        <section key={section} className="metrics-grid-section ed-section">
          <div className="metrics-section-kicker"><span>{section}</span></div>
          <div className="ed-loading-grid" aria-hidden="true">
            {Array.from({length:3},(_,i)=>
              <div key={i} className="ed-loading-card"><div/><div/><div/></div>)}
          </div>
        </section>)}
    </main>
  </div>;
}
