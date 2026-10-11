import type { Metadata } from "next";
import ProductMetricsHeader from "../../components/product-metrics-header";
import InfraOverview from "../../components/infra/infra-overview";
import { infraPreviewData } from "../../lib/infra/preview-snapshot";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "../delivery/delivery.css";
import "./infra.css";

export const metadata: Metadata = {
  title: "AI Accountant | Infrastructure Overview",
  description: "Read-only infrastructure dashboard preview using audited AWS and bill-processing aggregates.",
};

/** UI preview, NOT a live cost reader: no SQL or external billing API calls. */
export default function InfraPage() {
  return <div className="ed-shell infra-shell">
    <ProductMetricsHeader current="infra" />
    <InfraOverview data={infraPreviewData} />
  </div>;
}
