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
import { readOverviewRange, resolveOverviewRange } from "../../lib/overview/history";
import type { OverviewUsageSnapshot } from "../../lib/overview/kpis";
import type { OverviewActiveCharts } from "../../lib/overview/active-charts";
import type { AdoptionSummary } from "../../lib/overview/adoption";
import type { WorkflowSummary } from "../../lib/overview/workflow";
import type { FrictionSummary } from "../../lib/overview/friction";

export const dynamic = "force-dynamic";

export default async function OverviewPage({
  searchParams,
}: {
  searchParams: Promise<Record<string,string|string[]|undefined>>;
}) {
  const params=await searchParams;
  const invalidSelection=(params.from!==undefined || params.to!==undefined)
    && readOverviewRange(params)===null;
  let resolved=await resolveOverviewRange(readOverviewRange(params));
  if(invalidSelection)resolved={
    ...resolved,unsupported:true,historical:true,
  };
  // Never fall back to current production values for an unsupported date.
  const selected=resolved.unsupported ? undefined : resolved.snapshotId??undefined;
  const [kpiResult,chartResult,adoptionResult,workflowResult,frictionResult] = await Promise.allSettled([
    resolved.unsupported ? Promise.resolve(null as OverviewUsageSnapshot|null) : readPublishedOverviewUsage(selected),
    resolved.unsupported ? Promise.resolve(null as OverviewActiveCharts|null) : readPublishedOverviewActiveCharts(selected),
    resolved.unsupported ? Promise.resolve(null as AdoptionSummary|null) : readPublishedAdoptionSummary(selected),
    resolved.unsupported ? Promise.resolve(null as WorkflowSummary|null) : readPublishedWorkflowSummary(selected),
    resolved.unsupported ? Promise.resolve(null as FrictionSummary|null) : readPublishedFrictionSummary(selected),
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
  // Snapshot IDs, event cutoffs and source timestamps must match across the
  // five chart families; a partial historic dashboard is not publishable.
  const snapshots=[overviewKpis,overviewCharts,adoption,workflow,friction];
  const consistent=!resolved.historical || (
    snapshots.every(Boolean)
    && snapshots.every(x=>x?.snapshotId===resolved.snapshotId)
    && snapshots.every(x=>x?.asOf===overviewKpis?.asOf)
    && snapshots.every(x=>x?.sourceWatermarkAt===overviewKpis?.sourceWatermarkAt)
  );
  if(!consistent){
    console.error("overview-history-inconsistent",resolved.snapshotId);
  }
  const selectedData=consistent ? snapshots : [null,null,null,null,null];
  const [usage,charts,adoptionData,workflowData,frictionData]=selectedData;
  const starting=resolved.startMonth;
  const chartWeeks=charts && starting
    ? {...charts,weekly:{rows:charts.weekly.rows.filter(row=>row.week_start>=starting+"-01")}}
    : charts;
  const workflowWeeks=workflowData && starting
    ? {...workflowData,weekly:workflowData.weekly.filter(row=>row.week_start>=starting+"-01")}
    : workflowData;
  return <PrototypeSurface
    overviewKpis={usage as OverviewUsageSnapshot|null}
    overviewCharts={chartWeeks as OverviewActiveCharts|null}
    adoption={adoptionData as AdoptionSummary|null}
    workflow={workflowWeeks as WorkflowSummary|null}
    friction={frictionData as FrictionSummary|null}
    historicalStatus={resolved.historical
      ? (resolved.unsupported || !consistent?"unavailable":"available")
      : "current"}
    historyRangeStart={resolved.selection?.from??null}
  />;
}
