export default function AiServicesLoading() {
  return (
    <div className="ed-shell" role="status" aria-busy="true" aria-label="Loading bill extraction">
      <main className="rd-page ed-page">
        <div className="rd-page-head ed-page-head">
          <div className="ed-page-copy">
            <h1>Bill Extraction Overview</h1>
            <p>Loading synthetic demo data…</p>
          </div>
        </div>
        <section className="metrics-grid-section ed-section ai-kpi-section" aria-hidden="true">
          <div className="ed-quality-kpis ed-kpi-grid po-kpis">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="ed-metric-wrap"><div className="metric-card ed-metric" /></div>
          ))}
          </div>
        </section>
      </main>
    </div>
  );
}
