import { PrototypeSurface } from "../../components/prototype-surface";
import "../retention/retention.css";
import "./overview-kpi-drill.css";
import { readPublishedOverviewUsage } from "../../lib/overview/kpis";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";

export const dynamic = "force-dynamic";

export default async function OverviewPage() {
  let overviewKpis: OverviewUsageSnapshot | null = null;
  try {
    overviewKpis = await readPublishedOverviewUsage();
  } catch (error) {
    console.error(
      "overview-live-kpis",
      error instanceof Error ? error.message.slice(0, 120) : "unknown_error",
    );
  }
  return <PrototypeSurface overviewKpis={overviewKpis} />;
}
