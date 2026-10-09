"use client";

import Script from "next/script";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { prototypeMarkup } from "../lib/prototype/markup";
import { installCustomerNavigation, withCustomerNavigation } from "../lib/prototype/customer-navigation";
import type { OverviewUsageSnapshot } from "../lib/overview/kpis";
import type { OverviewActiveCharts } from "../lib/overview/active-charts";
import type { AdoptionSummary } from "../lib/overview/adoption";
import type { WorkflowSummary } from "../lib/overview/workflow";
import type { FrictionSummary } from "../lib/overview/friction";
import OverviewKpiStrip from "./overview/overview-kpi-strip";
import OverviewActiveUsage from "./overview/overview-active-usage";
import OverviewAdoption from "./overview/overview-adoption";
import OverviewWorkflow from "./overview/overview-workflow";
import OverviewFriction from "./overview/overview-friction";
import OverviewMetricInfo from "./overview/overview-info";
import ProductMetricsHeader from "./product-metrics-header";

const markup = withCustomerNavigation(prototypeMarkup);

/**
 * Compatibility boundary for the remaining approved prototype surfaces.
 * Native React owns the KPIs, Active Usage, Adoption & Value, Workflow Usage and Friction;
 * the legacy runtime is not allowed to write into those DOM targets.
 */
export function PrototypeSurface({
  overviewKpis,
  overviewCharts,
  adoption,
  workflow,
  friction,
}: {
  overviewKpis: OverviewUsageSnapshot | null;
  overviewCharts: OverviewActiveCharts | null;
  adoption: AdoptionSummary | null;
  workflow: WorkflowSummary | null;
  friction: FrictionSummary | null;
}) {
  const [baseReady, setBaseReady] = useState(false);
  const [frictionTarget, setFrictionTarget] = useState<HTMLElement | null>(null);
  const [overviewReady, setOverviewReady] = useState(false);
  const [kpiTarget, setKpiTarget] = useState<HTMLElement | null>(null);
  const [workflowTargets, setWorkflowTargets] = useState<{
    trend: HTMLElement;
    mix: HTMLElement;
  } | null>(null);
  const [adoptionTargets, setAdoptionTargets] = useState<{
    strip: HTMLElement;
    funnel: HTMLElement;
  } | null>(null);
  const [chartTargets, setChartTargets] = useState<{
    weekly: HTMLElement;
    frequency: HTMLElement;
  } | null>(null);

  useEffect(() => {
    setKpiTarget(document.getElementById("po-kpis"));
  }, []);

  useEffect(() => {
    if (overviewReady) return installCustomerNavigation();
  }, [overviewReady]);

  useEffect(() => {
    if (!overviewReady) return;
    const weekly = document.getElementById("po-weekly-chart-view");
    const frequency = document.getElementById("po-frequency-content");
    if (!weekly || !frequency) return;

    // These two report bodies are now React-controlled. Remove only their
    // static prototype children, not their approved card/header/footer shells.
    weekly.replaceChildren();
    frequency.replaceChildren();
    const oldTable = document.getElementById("po-weekly-data");
    oldTable?.replaceChildren();
    oldTable?.setAttribute("hidden", "");
    document.querySelector("#po-weekly-report .po-sample")?.remove();
    setChartTargets({ weekly, frequency });
  }, [overviewReady]);

  useEffect(() => {
    if (!overviewReady) return;
    const strip = document.getElementById("po-adoption-kpis");
    const funnel = document.getElementById("po-journey-live-content");
    if (strip && funnel) setAdoptionTargets({ strip, funnel });
  }, [overviewReady]);

  useEffect(() => {
    if (!overviewReady) return;
    const trend = document.getElementById("po-feature-chart-view");
    const mix = document.getElementById("po-mix-content");
    if (!trend || !mix) return;
    trend.replaceChildren();
    mix.replaceChildren();
    const oldTable = document.getElementById("po-feature-data");
    oldTable?.replaceChildren();
    oldTable?.setAttribute("hidden", "");
    document.querySelector("#po-feature-report .po-sample")?.remove();
    setWorkflowTargets({ trend, mix });
  }, [overviewReady]);

  useEffect(() => {
    if (!overviewReady) return;
    const target = document.getElementById("po-friction-content");
    if (!target) return;
    target.replaceChildren();
    setFrictionTarget(target);
  }, [overviewReady]);

  return (
    <>
      <ProductMetricsHeader current="overview" />
      <div
        id="prototype-surface"
        data-overview-as-of={overviewKpis?.asOfDate ?? ""}
        style={{ display: "contents" }}
        dangerouslySetInnerHTML={{ __html: markup }}
      />
      {kpiTarget
        ? createPortal(<OverviewKpiStrip snapshot={overviewKpis} />, kpiTarget)
        : null}
      {chartTargets ? (
        <OverviewActiveUsage
          snapshot={overviewKpis}
          charts={overviewCharts}
          weeklyTarget={chartTargets.weekly}
          frequencyTarget={chartTargets.frequency}
        />
      ) : null}
      {adoptionTargets ? (
        <OverviewAdoption
          summary={adoption}
          usageSnapshot={overviewKpis}
          stripTarget={adoptionTargets.strip}
          funnelTarget={adoptionTargets.funnel}
        />
      ) : null}
      {workflowTargets ? (
        <OverviewWorkflow
          summary={workflow}
          usageSnapshot={overviewKpis}
          trendTarget={workflowTargets.trend}
          mixTarget={workflowTargets.mix}
        />
      ) : null}
      {frictionTarget ? (
        <OverviewFriction
          summary={friction}
          usageSnapshot={overviewKpis}
          target={frictionTarget}
        />
      ) : null}
      <OverviewMetricInfo />
      <Script
        id="prototype-v2-base"
        src="/prototype/runtime-v2-1.js"
        strategy="afterInteractive"
        onReady={() => setBaseReady(true)}
      />
      {baseReady && (
        <Script
          id="prototype-v2-overview"
          src="/prototype/runtime-v2-2.js"
          strategy="afterInteractive"
          onReady={() => setOverviewReady(true)}
        />
      )}
    </>
  );
}
