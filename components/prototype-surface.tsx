"use client";

import Script from "next/script";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { prototypeMarkup } from "../lib/prototype/markup";
import { installCustomerNavigation, withCustomerNavigation } from "../lib/prototype/customer-navigation";
import type { OverviewUsageSnapshot } from "../lib/overview/kpis";
import OverviewKpiStrip from "./overview/overview-kpi-strip";

const markup = withCustomerNavigation(prototypeMarkup);

/**
 * The approved prototype retains ownership of report/chart fixtures.
 * Only the Product Overview KPI strip is migrated into native React.
 * The legacy runtime must never write into #po-kpis.
 */
export function PrototypeSurface({
  overviewKpis,
}: {
  overviewKpis: OverviewUsageSnapshot | null;
}) {
  const [baseReady, setBaseReady] = useState(false);
  const [overviewReady, setOverviewReady] = useState(false);
  const [kpiTarget, setKpiTarget] = useState<HTMLElement | null>(null);

  useEffect(() => {
    setKpiTarget(document.getElementById("po-kpis"));
  }, []);

  useEffect(() => {
    if (overviewReady) return installCustomerNavigation();
  }, [overviewReady]);

  return (
    <>
      <div
        id="prototype-surface"
        data-overview-as-of={overviewKpis?.asOfDate ?? ""}
        style={{ display: "contents" }}
        dangerouslySetInnerHTML={{ __html: markup }}
      />
      {kpiTarget
        ? createPortal(<OverviewKpiStrip snapshot={overviewKpis} />, kpiTarget)
        : null}
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
