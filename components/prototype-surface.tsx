"use client";

import Script from "next/script";
import { useEffect, useState } from "react";
import { prototypeMarkup } from "../lib/prototype/markup";
import { installCustomerNavigation, withCustomerNavigation } from "../lib/prototype/customer-navigation";

const markup = withCustomerNavigation(prototypeMarkup);

/**
 * Compatibility boundary: the approved prototype owns this DOM subtree.
 * React owns its stable container and ordered script loading only.
 * The Customer route is a separate, fully React-owned surface.
 */
export function PrototypeSurface() {
  const [baseReady, setBaseReady] = useState(false);
  const [overviewReady, setOverviewReady] = useState(false);
  useEffect(() => {
    if (overviewReady) return installCustomerNavigation();
  }, [overviewReady]);
  return <>
    <div id="prototype-surface" style={{ display: "contents" }} dangerouslySetInnerHTML={{ __html: markup }} />
    <Script id="prototype-v2-base" src="/prototype/runtime-v2-1.js" strategy="afterInteractive" onReady={() => setBaseReady(true)} />
    {baseReady && <Script id="prototype-v2-overview" src="/prototype/runtime-v2-2.js" strategy="afterInteractive" onReady={() => setOverviewReady(true)} />}
  </>;
}
