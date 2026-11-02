import type { Metadata } from "next";
import ProductMetricsHeader from "../../components/product-metrics-header";
import InfraOverview from "../../components/infra/infra-overview";
import { readInfraAwsLive } from "../../lib/infra/live";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "../delivery/delivery.css";
import "../delivery/delivery-investigation.css";
import "./infra.css";

export const metadata: Metadata = {
  title: "AI Accountant | Infrastructure Overview",
  description: "Live AWS Cost Explorer spending, refreshed from verified daily Supabase syncs.",
};

/** Live read-only report. */
export const dynamic = "force-dynamic";
export default async function InfraPage() {
  const data = await readInfraAwsLive();
  return <div className="ed-shell infra-shell">
    <ProductMetricsHeader current="infra" />
    <InfraOverview data={data} />
  </div>;
}
