import type { Metadata } from "next";
import ProductMetricsHeader from "../../components/product-metrics-header";
import EngineeringDeliveryShell from "../../components/delivery/engineering-delivery-shell";
import { parseDeliveryFilters, readDeliveryDashboard } from "../../lib/delivery/server";
import type { DeliveryDashboard, DeliveryFilters } from "../../lib/delivery/types";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "./delivery.css";

export const metadata: Metadata = {
  title: "AI Accountant | Engineering & Delivery",
  description: "Verified Jira sprint delivery, attention, flow and engineering quality.",
};
export const dynamic = "force-dynamic";

/** The shared Product grid is retained. The only data source is the
 * service-role-only Jira reporting facade; screenshot fixtures are forbidden. */
export default async function DeliveryPage({
  searchParams,
}: {
  searchParams: Promise<Record<string,string|string[]|undefined>>;
}) {
  let dashboard: DeliveryDashboard | null = null;
  let filters: DeliveryFilters = {
    sprint: null, module: null, sub_module: null, severity: null, assignee: null,
  };
  let message: string | null = null;
  try {
    filters = parseDeliveryFilters(await searchParams);
    dashboard = await readDeliveryDashboard(filters);
  } catch (error) {
    console.error("delivery_dashboard_unavailable",
      error instanceof Error ? error.message.slice(0,145) : "unknown");
    message = "Verified Jira metrics are temporarily unavailable. No stale or sample values are being shown.";
  }
  return (
    <div className="ed-shell">
      <ProductMetricsHeader current="delivery" />
      <EngineeringDeliveryShell data={dashboard} filters={filters} error={message} />
    </div>
  );
}
