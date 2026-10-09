"use client";

import React from "react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuLinkItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";

export type DashboardKey = "overview" | "retention" | "companies";

const DASHBOARDS = [
  {
    key: "overview" as const,
    name: "Product Overview",
    description: "Active usage, adoption and workflow health",
    href: "/overview",
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

function HeaderIcon({
  name,
}: {
  name: "grid" | "down" | "check";
}) {
  const path =
    name === "down"
      ? "m7 10 5 5 5-5"
      : name === "check"
        ? "m5 12 4 4L19 6"
        : null;

  return (
    <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
      {name === "grid" ? (
        <>
          <rect x="3.5" y="3.5" width="6" height="6" rx="1" />
          <rect x="14.5" y="3.5" width="6" height="6" rx="1" />
          <rect x="3.5" y="14.5" width="6" height="6" rx="1" />
          <rect x="14.5" y="14.5" width="6" height="6" rx="1" />
        </>
      ) : (
        <path d={path ?? ""} />
      )}
    </svg>
  );
}

/**
 * One React header for Product Overview, Retention & Churn, and Companies.
 * The dropdown uses the shadcn Base UI Menu primitives, not the old
 * hand-managed prototype popover. Chart help remains in individual cards.
 */
export default function ProductMetricsHeader({
  current,
}: {
  current: DashboardKey;
}) {
  const active = DASHBOARDS.find(item => item.key === current) ?? DASHBOARDS[0];

  return (
    <header className="app-header product-metrics-header">
      <div className="brand-left">
        <div className="brand">
          <span className="brand-mark">
            <HeaderIcon name="grid" />
          </span>
          AI Accountant
        </div>
        <span className="brand-divider" />
        <span className="product-name">Product Metrics</span>
      </div>

      <nav aria-label="Product metrics navigation" className="top-nav">
        <DropdownMenu>
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
        </DropdownMenu>
      </nav>
    </header>
  );
}
