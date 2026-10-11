"use client";

import React from "react";
import { useRouter } from "next/navigation";
import MainNavigationDrawer from "./main-navigation-drawer";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuLinkItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";

export type DashboardKey = "product" | "retention" | "companies" | "delivery" | "infra";
export type DeliveryView = "overview" | "assignees";

const ENGINEERING_PAGES = [
  {key:"overview" as const,name:"Engineering Overview",
   description:"Sprint, flow and quality reporting",href:"/delivery"},
  {key:"assignees" as const,name:"Assignee Overview",
   description:"Ownership by module and issue type",href:"/delivery/assignees"},
];
const INFRA_PAGES = [
  {key:"overview" as const,name:"Infrastructure Overview",
   description:"Cloud spend, processing economics and data confidence",href:"/infra"},
];
const DASHBOARDS = [
  {
    key: "product" as const,
    name: "Product Overview",
    description: "Active usage, adoption and workflow health",
    href: "/product",
  },
  {
    key: "retention" as const,
    name: "Retention & Churn",
    description: "Activation, retention and monthly churn",
    href: "/retention",
  },
  {
    key: "companies" as const,
    name: "Companies",
    description: "Monthly usage by company and user",
    href: "/customer",
  },
];

function HeaderIcon({ name }: { name: "down" | "check" }) {
  const path = name === "down" ? "m7 10 5 5 5-5" : "m5 12 4 4L19 6";
  return (
    <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
      <path d={path} />
    </svg>
  );
}

/**
 * One React header for Product Overview, Retention & Churn, and Companies.
 * The dropdown uses the shadcn Base UI Menu primitives, not the old
 * hand-managed prototype popover. Chart help remains in individual cards.
 */
export default function ProductMetricsHeader({
  current,deliveryView="overview",
}: {
  current: DashboardKey;
  deliveryView?:DeliveryView;
}) {
  const router = useRouter();
  const isDelivery = current === "delivery";
  const isInfra = current === "infra";
  const active = DASHBOARDS.find(item => item.key === current) ?? DASHBOARDS[0];
  const deliveryCurrent=ENGINEERING_PAGES.find(item=>item.key===deliveryView)??ENGINEERING_PAGES[0];
  const sectionPages=isInfra?INFRA_PAGES:ENGINEERING_PAGES;
  const sectionCurrent=isInfra?INFRA_PAGES[0]:deliveryCurrent;

  return (
    <header className="app-header product-metrics-header">
      <div className="brand-left">
        <div className="brand">
          <MainNavigationDrawer />
          AI Accountant
        </div>
        <span className="brand-divider" />
        <span className="product-name">{isInfra?"Infrastructure Metrics":isDelivery ? "Engineering Metrics" : "Product Metrics"}</span>
      </div>

      <nav aria-label={isInfra?"Infrastructure navigation":isDelivery ? "Engineering navigation" : "Product metrics navigation"} className="top-nav">
        {isDelivery || isInfra ? (
          <DropdownMenu>
            <DropdownMenuTrigger className="app-dashboard-trigger"
              aria-label={(isInfra?"Infrastructure pages, currently ":"Engineering pages, currently ")+sectionCurrent.name}>
              <span>{sectionCurrent.name}</span>
              <HeaderIcon name="down" />
            </DropdownMenuTrigger>
            <DropdownMenuContent aria-label={isInfra?"Infrastructure pages":"Engineering pages"} align="end" sideOffset={8}>
              <DropdownMenuGroup>
                <DropdownMenuLabel className="app-dashboard-menu-label">{isInfra?"Infrastructure":"Engineering"}</DropdownMenuLabel>
                {sectionPages.map(item=>{
                  const selected=isInfra?item.key==="overview":item.key===deliveryView;
                  return <DropdownMenuLinkItem key={item.key} href={item.href}
                    aria-current={selected?"page":undefined} className="app-dashboard-item"
                    onClick={event=>{
                      if(selected){event.preventDefault();return;}
                      // Client transition preserves the already-loaded app shell
                      // and shows the destination loading skeleton immediately.
                      // Modified clicks keep native new-tab navigation behavior.
                      if(event.defaultPrevented||event.button!==0||
                        event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
                      event.preventDefault();
                      router.push(item.href);
                    }}>
                    <span className="app-dashboard-item-label">
                      <strong>{item.name}</strong><small>{item.description}</small>
                    </span>
                    {selected?<span className="app-dashboard-current" aria-hidden="true">
                      <HeaderIcon name="check" />
                    </span>:null}
                  </DropdownMenuLinkItem>;
                })}
              </DropdownMenuGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        ) : <DropdownMenu>
          <DropdownMenuTrigger
            className="app-dashboard-trigger"
            aria-label={"Dashboards, currently " + active.name}
          >
            <span>{active.name}</span>
            <HeaderIcon name="down" />
          </DropdownMenuTrigger>

          <DropdownMenuContent aria-label="Dashboards" align="end" sideOffset={8}>
            <DropdownMenuGroup>
              <DropdownMenuLabel className="app-dashboard-menu-label">
                Dashboards
              </DropdownMenuLabel>
              {DASHBOARDS.map(item => {
                const selected = item.key === current;
                return (
                  <DropdownMenuLinkItem
                    key={item.key}
                    href={item.href}
                    aria-current={selected ? "page" : undefined}
                    className="app-dashboard-item"
                    onClick={event => {
                      if (selected) event.preventDefault();
                    }}
                  >
                    <span className="app-dashboard-item-label">
                      <strong>{item.name}</strong>
                      <small>{item.description}</small>
                    </span>
                    {selected ? (
                      <span className="app-dashboard-current" aria-hidden="true">
                        <HeaderIcon name="check" />
                      </span>
                    ) : null}
                  </DropdownMenuLinkItem>
                );
              })}
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>}
      </nav>
    </header>
  );
}
