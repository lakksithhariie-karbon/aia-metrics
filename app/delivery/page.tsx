import type { Metadata } from "next";
import ProductMetricsHeader from "../../components/product-metrics-header";
import EngineeringDeliveryShell from "../../components/delivery/engineering-delivery-shell";
import "../retention/retention.css";
import "../metrics-page-grid.css";
import "./delivery.css";

export const metadata: Metadata = {
  title: "AI Accountant | Engineering & Delivery",
  description: "Engineering sprint delivery, issue flow, attention and quality.",
};

/**
 * Preview-stage Engineering & Delivery route.
 *
 * Reuses Product Overview / Retention's common page grid and card system.
 * No Jira metrics are synthesized or fetched in this shell-only phase.
 */
export default function DeliveryPage() {
  return (
    <div className="ed-shell">
      <ProductMetricsHeader current="delivery" />
      <EngineeringDeliveryShell />
    </div>
  );
}
