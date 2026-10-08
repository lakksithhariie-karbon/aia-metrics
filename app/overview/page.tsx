import { PrototypeSurface } from "../../components/prototype-surface";
import "../retention/retention.css";
import "./overview-kpi-drill.css";
import "./overview-active-usage.css";
import "./overview-adoption.css";
import "./overview-workflow.css";
import "./overview-friction.css";
import "./overview-info.css";
import { readPublishedOverviewUsage } from "../../lib/overview/kpis";
import { readPublishedOverviewActiveCharts } from "../../lib/overview/active-charts";
import { readPublishedAdoptionSummary } from "../../lib/overview/adoption";
import { readPublishedWorkflowSummary } from "../../lib/overview/workflow";
import { readPublishedFrictionSummary } from "../../lib/overview/friction";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type { OverviewActiveCharts } from "../../lib/overview/active-charts";
import type { AdoptionSummary } from "../../lib/overview/adoption";
import type { WorkflowSummary } from "../../lib/overview/workflow";
import type { FrictionSummary } from "../../lib/overview/friction";

export const dynamic = "force-dynamic";

export default async function OverviewPage() {
  const [kpiResult,chartResult,adoptionResult,workflowResult,frictionResult] = await Promise.allSettled([
    readPublishedOverviewUsage(),
    readPublishedOverviewActiveCharts(),
    readPublishedAdoptionSummary(),
    readPublishedWorkflowSummary(),
    readPublishedFrictionSummary(),
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
  if(workflowResult.status==="rejected") {
    console.error("overview-live-workflow",
      workflowResult.reason instanceof Error ? workflowResult.reason.message.slice(0,120) : "unknown_error");
  }
  if(frictionResult.status==="rejected") {
    console.error("overview-live-friction",
      frictionResult.reason instanceof Error ? frictionResult.reason.message.slice(0,120) : "unknown_error");
  }
  const friction: FrictionSummary|null =
    frictionResult.status==="fulfilled" ? frictionResult.value : null;
  const workflow: WorkflowSummary|null =
    workflowResult.status==="fulfilled" ? workflowResult.value : null;
  const adoption: AdoptionSummary|null =
    adoptionResult.status==="fulfilled" ? adoptionResult.value : null;
  const overviewKpis: OverviewUsageSnapshot|null =
    kpiResult.status==="fulfilled" ? kpiResult.value : null;
  const overviewCharts: OverviewActiveCharts|null =
    chartResult.status==="fulfilled" ? chartResult.value : null;
  return <PrototypeSurface overviewKpis={overviewKpis} overviewCharts={overviewCharts} adoption={adoption} workflow={workflow} friction={friction}/>;
}
