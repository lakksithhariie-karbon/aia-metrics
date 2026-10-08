import { PrototypeSurface } from "../../components/prototype-surface";
import "../retention/retention.css";
import "./overview-kpi-drill.css";
import "./overview-active-usage.css";
import "./overview-adoption.css";
import { readPublishedOverviewUsage } from "../../lib/overview/kpis";
import { readPublishedOverviewActiveCharts } from "../../lib/overview/active-charts";
import { readPublishedAdoptionSummary } from "../../lib/overview/adoption";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type { OverviewActiveCharts } from "../../lib/overview/active-charts";
import type { AdoptionSummary } from "../../lib/overview/adoption";

export const dynamic = "force-dynamic";

export default async function OverviewPage() {
  const [kpiResult,chartResult,adoptionResult] = await Promise.allSettled([
    readPublishedOverviewUsage(),
    readPublishedOverviewActiveCharts(),
    readPublishedAdoptionSummary(),
  ]);
  if(kpiResult.status==="rejected") {
    console.error("overview-live-kpis",
      kpiResult.reason instanceof Error ? kpiResult.reason.message.slice(0,120) : "unknown_error");
  }
  if(chartResult.status==="rejected") {
    console.error("overview-live-charts",
      chartResult.reason instanceof Error ? chartResult.reason.message.slice(0,120) : "unknown_error");
  }
  if(adoptionResult.status==="rejected") {
    console.error("overview-live-adoption",
      adoptionResult.reason instanceof Error ? adoptionResult.reason.message.slice(0,120) : "unknown_error");
  }
  const adoption: AdoptionSummary|null =
    adoptionResult.status==="fulfilled" ? adoptionResult.value : null;
  const overviewKpis: OverviewUsageSnapshot|null =
    kpiResult.status==="fulfilled" ? kpiResult.value : null;
  const overviewCharts: OverviewActiveCharts|null =
    chartResult.status==="fulfilled" ? chartResult.value : null;
  return <PrototypeSurface overviewKpis={overviewKpis} overviewCharts={overviewCharts} adoption={adoption}/>;
}
