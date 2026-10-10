import ProductMetricsHeader from "../../components/product-metrics-header";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "./delivery.css";
export default function LoadingDelivery() {
  return (
    <div className="ed-shell">
      <ProductMetricsHeader current="delivery"/>
      <main className="rd-page ed-page" role="status" aria-busy="true" aria-label="Loading verified Jira delivery dashboard">
        <div className="rd-page-head ed-page-head">
          <div className="ed-page-copy">
            <h1>Engineering &amp; Delivery</h1>
            <p>Loading verified Jira reporting data…</p>
          </div>
        </div>
        {["Sprint delivery","Attention","Delivery","Flow","Quality"].map(name=>(
          <section key={name} className="metrics-grid-section ed-section">
            <div className="metrics-section-kicker"><span>{name}</span></div>
            <div className="ed-loading-grid" aria-hidden="true">
              {Array.from({length:3},(_,index)=>(
                <div key={index} className="ed-loading-card">
                  <div/><div/><div/>
                </div>
              ))}
            </div>
          </section>
        ))}
      </main>
    </div>
  );
}
