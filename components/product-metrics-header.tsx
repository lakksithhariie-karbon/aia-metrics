"use client";

import React, { useState } from "react";

type DashboardKey = "overview" | "retention" | "companies";

const DASHBOARDS = [
  {
    key: "overview" as const,
    name: "Product Overview",
    description: "Active usage, adoption and workflow health",
    href: "/overview",
    icon: "grid" as const,
  },
  {
    key: "retention" as const,
    name: "Retention & Churn",
    description: "Activation, retention and monthly churn",
    href: "/retention",
    icon: "trend" as const,
  },
  {
    key: "companies" as const,
    name: "Companies",
    description: "Monthly usage by integration cohort",
    href: "/customer",
    icon: "grid" as const,
  },
];

function HeaderIcon({
  name,
}: {
  name: "grid" | "trend" | "down" | "check" | "help";
}) {
  const path =
    name === "trend"
      ? "m3 17 6-6 4 4 8-10m-6 0h6v6"
      : name === "down"
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
      ) : name === "help" ? (
        <>
          <circle cx="12" cy="12" r="9" />
          <path d="M9.5 8.7a2.6 2.6 0 0 1 5 1c0 1.8-2.5 2-2.5 3.8M12 16.8v.1" />
        </>
      ) : (
        <path d={path ?? ""} />
      )}
    </svg>
  );
}

export default function ProductMetricsHeader({
  current,
  onHelp,
}: {
  current: DashboardKey;
  onHelp?: () => void;
}) {
  const [open, setOpen] = useState(false);
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
        <div className="dashboard-switcher">
          <button
            className="dashboard-trigger ui-control"
            type="button"
            aria-haspopup="menu"
            aria-expanded={open}
            onClick={() => setOpen(value => !value)}
          >
            <HeaderIcon name={active.icon} />
            <span>{active.name}</span>
            <HeaderIcon name="down" />
          </button>

          <div
            className="dashboard-menu ui-menu-surface"
            role="menu"
            hidden={!open}
          >
            <div className="menu-heading" role="presentation">
              Dashboards
            </div>
            {DASHBOARDS.map(item => (
              <a
                key={item.key}
                href={item.href}
                role="menuitemradio"
                aria-checked={item.key === current}
                className={
                  "dashboard-option " +
                  (item.key === current ? "is-current" : "")
                }
                onClick={event => {
                  if (item.key === current) {
                    event.preventDefault();
                    setOpen(false);
                  }
                }}
              >
                <span className="menu-option-icon">
                  <HeaderIcon name={item.icon} />
                </span>
                <span className="menu-option-copy">
                  <strong>{item.name}</strong>
                  <small>{item.description}</small>
                </span>
                {item.key === current ? <HeaderIcon name="check" /> : null}
              </a>
            ))}
          </div>
        </div>

        <button
          className="header-help"
          type="button"
          aria-label="Metric definitions"
          title="Metric definitions"
          onClick={onHelp}
        >
          <HeaderIcon name="help" />
        </button>
      </nav>
    </header>
  );
}
