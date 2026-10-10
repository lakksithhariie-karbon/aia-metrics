"use client";

import { useEffect, useRef } from "react";
import type { MouseEvent } from "react";

export type MetricsInfoKey =
  | "activation" | "ttv" | "monthly_churn"
  | "retention_cohorts" | "churn_trend" | "companies_monthly";

export interface MetricsInfoDefinition {
  title: string;
  logic: string;
  example: string;
  note?: string;
}

export const metricsInfoDefinitions: Record<MetricsInfoKey, MetricsInfoDefinition> = {
  activation: {
    title: "Activation rate",
    logic: "Activated companies ÷ companies with a recorded successful integration in the selected dates. Activation requires a qualifying sync, core work on a later IST day, then another qualifying sync.",
    example: "4 activated / 20 integrated = 20%.",
    note: "May–July tracking gaps can exclude integrations. Marked test companies are included.",
  },
  ttv: {
    title: "Average time to value",
    logic: "Average elapsed time from first recorded successful integration to the sync completing activation, among activated companies.",
    example: "Two companies take 2 and 6 days: average = 4 days.",
  },
  monthly_churn: {
    title: "Monthly churn",
    logic: "Activated companies with no recorded core activity in the last completed IST month ÷ companies activated before that month.",
    example: "5 inactive / 20 eligible = 25% churn.",
    note: "Retention's core activity includes Accounting Sync. Marked test companies are included.",
  },
  retention_cohorts: {
    title: "Retention",
    logic: "For each activation-week or activation-month cohort, count companies active in each subsequent completed period ÷ the original cohort size.",
    example: "4 active out of 10 in Week 1 = 40%.",
    note: "Accounting Sync can qualify as activity here. May–July telemetry is incomplete.",
  },
  churn_trend: {
    title: "Month-on-Month Churn Trend",
    logic: "For each completed IST month: churned companies ÷ companies activated before the month. Entered = newly churned; Reactivated = churned last month but active now.",
    example: "Rate rises from 20% to 26%: +6 percentage points.",
    note: "Core activity here includes Accounting Sync.",
  },
  companies_monthly: {
    title: "Monthly company module usage",
    logic: "Companies are grouped by first recorded integration month. Each cell counts mapped AP, AR, Transactions or GST event occurrences after integration, in that IST calendar month.",
    example: "3 bill-upload events + 2 transaction edits = AP 3, Transactions 2.",
    note: "Counts include failed attempts, downloads and deletions, not just completed work. Invoice bulk edits currently map to AP. Test companies can appear.",
  },
};

export function MetricsInfoButton({
  label,
  onClick,
  className = "",
}: {
  label: string;
  onClick: (event: MouseEvent<HTMLButtonElement>) => void;
  className?: string;
}) {
  return (
    <button
      type="button"
      className={"metrics-info-trigger " + className}
      title="How it's counted"
      aria-label={label}
      onClick={event => {
        event.preventDefault();
        event.stopPropagation();
        onClick(event);
      }}
    >
      <svg aria-hidden="true" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="9" />
        <path d="M12 10.5v6M12 7.3v.1" />
      </svg>
    </button>
  );
}

export default function MetricsInfoDialog({
  definition,
  onClose,
}: {
  definition: MetricsInfoDefinition;
  onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const el = dialog.current;
    if (!el) return;
    if (!el.open) el.showModal();
    return () => {
      if (el.open) el.close();
    };
  }, []);

  return (
    <dialog
      ref={dialog}
      className="metrics-info-dialog"
      aria-labelledby="metrics-info-title"
      onClose={onClose}
      onClick={event => {
        if (event.target !== event.currentTarget) return;
        const box = event.currentTarget.getBoundingClientRect();
        const outside =
          event.clientX < box.left || event.clientX > box.right ||
          event.clientY < box.top || event.clientY > box.bottom;
        if (outside) dialog.current?.close();
      }}
    >
      <header className="metrics-info-head">
        <div>
          <p>Product Metrics · How it's counted</p>
          <h2 id="metrics-info-title">{definition.title}</h2>
        </div>
        <button
          type="button"
          className="metrics-info-trigger metrics-info-close"
          aria-label="Close explanation"
          onClick={() => dialog.current?.close()}
        >
          <svg aria-hidden="true" viewBox="0 0 24 24">
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </button>
      </header>
      <div className="metrics-info-body">
        <h3>Logic</h3>
        <p>{definition.logic}</p>
        <div className="metrics-info-example">
          <strong>Example</strong>
          <p>{definition.example}</p>
        </div>
        {definition.note ? <p className="metrics-info-note">{definition.note}</p> : null}
      </div>
    </dialog>
  );
}
