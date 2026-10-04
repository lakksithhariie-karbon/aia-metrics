"use client";

import Script from "next/script";
import { useState } from "react";
import { prototypeMarkup } from "../lib/prototype/markup";

/**
 * Compatibility boundary: the approved prototype owns this DOM subtree.
 * React owns its stable container and ordered script loading only.
 * Do not mix React-managed children into the imperative prototype DOM.
 * Replace one complete surface at a time when introducing typed data adapters.
 */
export function PrototypeSurface() {
  const [baseReady, setBaseReady] = useState(false);
  return <>
    <div id="prototype-surface" style={{ display: "contents" }} dangerouslySetInnerHTML={{ __html: prototypeMarkup }} />
    <Script id="prototype-v2-base" src="/prototype/runtime-v2-1.js" strategy="afterInteractive" onReady={() => setBaseReady(true)} />
    {baseReady && <Script id="prototype-v2-overview" src="/prototype/runtime-v2-2.js" strategy="afterInteractive" />}
  </>;
}
