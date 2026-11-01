import ProductMetricsHeader from "../../components/product-metrics-header";
import AiServicesOverview from "../../components/ai-services/ai-services-overview";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "../delivery/delivery.css";
import "../delivery/delivery-investigation.css";
import "./ai-services.css";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "AI Accountant | AI Services — Bill Extraction",
};

export default function AiServicesPage() {
  return (
    <>
      <ProductMetricsHeader current="ai-services" />
      <AiServicesOverview />
    </>
  );
}
