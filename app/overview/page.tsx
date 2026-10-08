import { PrototypeSurface } from "../../components/prototype-surface";
import "../retention/retention.css";
import "./overview-kpi-drill.css";
import "./overview-active-usage.css";
import { readPublishedOverviewUsage } from "../../lib/overview/kpis";
import { readPublishedOverviewActiveCharts } from "../../lib/overview/active-charts";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type { OverviewActiveCharts } from "../../lib/overview/active-charts";

export const dynamic = "force-dynamic";

export default async function OverviewPage() {
  const [kpiResult,chartResult] = await Promise.allSettled([
    readPublishedOverviewUsage(),
    readPublishedOverviewActiveCharts(),
  ]);
  if(kpiResult.status==="rejected") {
    console.error("overview-live-kpis",
      kpiResult.reason instanceof Error ? kpiResult.reason.message.slice(0,120) : "unknown_error");
  }
  if(chartResult.status==="rejected") {
    console.error("overview-live-charts",
      chartResult.reason instanceof Error ? chartResult.reason.message.slice(0,120) : "unknown_error");
  }
  const overviewKpis: OverviewUsageSnapshot|null =
    kpiResult.status==="fulfilled" ? kpiResult.value : null;
  const overviewCharts: OverviewActiveCharts|null =
    chartResult.status==="fulfilled" ? chartResult.value : null;
  return <PrototypeSurface overviewKpis={overviewKpis} overviewCharts={overviewCharts}/>;
}
