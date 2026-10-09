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
    logic: "Of client companies with a recorded successful integration in the selected date range, count those completing the full activation sequence: training sync, independent non-failed core work on a later IST day, and a subsequent qualifying Accounting Sync. Divide activated companies by eligible integrations.",
    example: "4 out of 20 integrated companies complete that sequence. The activation rate is 20%.",
    note: "Only recorded integration and activity events qualify. Internal staff are excluded.",
  },
  ttv: {
    title: "Average time to value",
    logic: "For activated companies with both recorded timestamps, calculate elapsed time from their first successful integration to the sync that completes activation. Show the average, converted from hours to days.",
    example: "If two eligible activated companies take 2 and 6 days to complete activation, average TTV is 4 days.",
    note: "Companies without a measurable activation-closing sync are excluded from the average.",
  },
  monthly_churn: {
    title: "Monthly churn",
    logic: "For the latest completed IST calendar month, divide activated companies with no qualifying core activity that month by companies activated before that month began.",
    example: "If 100 companies were eligible at the start of September and 25 recorded no core work, September churn is 25%.",
  },
  retention_cohorts: {
    title: "Retention",
    logic: "Group companies by the week or month in which they activated. For each subsequent completed IST week or month, divide companies with at least one qualifying non-failed core event in that period by the original activated cohort. The Average row pools eligible companies across cohorts.",
    example: "A cohort contains 10 activated companies. If 4 have core activity in Week 1, that cell is 40% (4/10).",
    note: "Ineligible or incomplete periods show a dash, not zero. Historical tracking gaps can depress observed retention.",
  },
  churn_trend: {
    title: "Month-on-Month Churn Trend",
    logic: "For each completed IST month, churned ÷ eligible activated companies gives the monthly churn rate. 'Entered' means newly churned this month (including newly eligible companies). 'Reactivated' means churned last month but active this month. 'vs prev' is the rate change in percentage points.",
    example: "If churn moves from 20% in August to 26% in September, the change is +6 percentage points.",
    note: "Click a completed month to inspect its companies and observed users.",
  },
  companies_monthly: {
    title: "Monthly company module usage",
    logic: "Assign each client company to its first successful integration month. For every displayed IST calendar month, count its qualifying logged AP, AR, Transactions and GST event occurrences, not unique documents or affected-item quantities. In the integration month, events before integration are excluded. Expand a company to see attributed users.",
    example: "A company integrated in August records 3 AP actions and 2 Transactions actions in September: its September cells show AP 3 and Transactions 2.",
    note: "A zero means no mapped event after integration. A dash means the company had not integrated. Internal users are excluded; unattributed activity may be displayed separately.",
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
