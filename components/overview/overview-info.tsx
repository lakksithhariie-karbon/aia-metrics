"use client";

import { useEffect, useRef, useState } from "react";

export type OverviewInfoKey =
  | "wau" | "mau" | "stickiness"
  | "weekly" | "frequency"
  | "core_7d" | "value_28d" | "sustained_28d"
  | "journey" | "feature" | "mix" | "friction";

type Definition = {
  title: string;
  rule: string;
  example: string;
  note?: string;
};

export const overviewDefinitions: Record<OverviewInfoKey, Definition> = {
  wau: {
    title: "Weekly core-active users",
    rule: "Distinct users with non-failed independent AP, AR or Transactions work in the last rolling 7 days. Accounting Sync does not count.",
    example: "One user uploads five bills: 1 active user.",
    note: "Marked test companies are currently included.",
  },
  mau: {
    title: "Monthly core-active users",
    rule: "Distinct users with independent core work in the last rolling 30 days. Same action rules as WAU.",
    example: "One user works on 10 days: 1 active user.",
    note: "Marked test companies are currently included.",
  },
  stickiness: {
    title: "Stickiness",
    rule: "Rolling 7-day active users ÷ rolling 30-day active users × 100.",
    example: "150 weekly / 500 monthly = 30%.",
  },
  weekly: {
    title: "Weekly core-active users",
    rule: "Distinct independent core-active users in each of 12 completed IST weeks. First observed = first recorded active week; Returning = recorded earlier.",
    example: "50 active, 8 first observed: 42 returning.",
    note: "First observed is not signup. May–July 2026 tracking was incomplete.",
  },
  frequency: {
    title: "Core usage frequency",
    rule: "Count how many of the last 4 completed IST weeks each user did independent core work. Each user enters exactly one bucket.",
    example: "Work in weeks 1 and 3 = Exactly 2 weeks.",
  },
  core_7d: {
    title: "7-day core adoption",
    rule: "Companies doing independent core work within 7 days of recorded integration ÷ integrated companies with a complete 28-day observation window.",
    example: "6 of 10 mature integrations start work = 60%.",
    note: "Missing integration events can exclude real customers.",
  },
  value_28d: {
    title: "28-day value conversion",
    rule: "Mature integrations completing training sync (>0 items), core work on a later IST day, then a closing sync (>0 items), all within 28 days.",
    example: "Day 1 sync → day 2 core work → day 3 sync: converted.",
    note: "This is stricter than the journey's post-work sync stage.",
  },
  sustained_28d: {
    title: "28-day sustained adoption",
    rule: "Mature integrations with independent core work in at least 2 of their first 4 integration-relative weeks ÷ all mature integrations.",
    example: "Work in weeks 1 and 3 qualifies; twice in week 1 does not.",
  },
  journey: {
    title: "Integration journey",
    rule: "Mature integrations → core work within 7 days → qualifying sync after that work, within 28 days. Each stage reports previous-stage and total-cohort conversion.",
    example: "10 integrated → 6 worked → 4 synced: 4/6 next-step, 4/10 total.",
    note: "The final journey stage is not the 28-day value-conversion milestone.",
  },
  feature: {
    title: "Module usage over time",
    rule: "Distinct users performing non-failed independent AP, AR or Transactions work per completed IST week, across 12 weeks.",
    example: "Bills and Transactions work in one week counts once in each line.",
  },
  mix: {
    title: "Module combinations",
    rule: "Each independently core-active company belongs to one exact AP/AR/Transactions combination per rolling 28 days. Compare shares with the previous 28 days.",
    example: "3 of 10 companies use AP + Transactions only = 30%.",
    note: "Marked test companies are currently included.",
  },
  friction: {
    title: "Issues that need attention",
    rule: "Incidence = companies with a recorded failure or review revert ÷ companies attempting that workflow in 28 days. Later success means another successful event in that company/workflow.",
    example: "3 failed out of 20 companies = 15% incidence.",
    note: "Later success is not a verified fix. Invoice bulk-edit failures are not in this table.",
  },
};

function validKey(value: string | undefined): value is OverviewInfoKey {
  return !!value && Object.prototype.hasOwnProperty.call(overviewDefinitions, value);
}

/** A separately focusable control alongside, never inside, a KPI drill button. */
export function OverviewInfoButton({ infoKey }: { infoKey: OverviewInfoKey }) {
  return (
    <button
      type="button"
      className="po-kpi-info-button icon-button"
      data-po-help={infoKey}
      aria-label={"How " + overviewDefinitions[infoKey].title + " is calculated"}
      title="How it's counted"
    >
      <svg className="icon" aria-hidden="true"><use href="#i-info" /></svg>
    </button>
  );
}

/** One short, consistent definition for every Overview card and chart.
 * Delegation supports native React cards and prototype-shell chart headers.
 */
export default function OverviewMetricInfo() {
  const [active, setActive] = useState<OverviewInfoKey | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const opener = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      if (!(event.target instanceof Element)) return;
      const button = event.target.closest<HTMLButtonElement>("button[data-po-help]");
      const key = button?.dataset.poHelp;
      if (!button || !validKey(key)) return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      opener.current = button;
      setActive(key);
    };
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, []);

  useEffect(() => {
    const el = dialog.current;
    if (!el) return;
    if (active && !el.open) el.showModal();
    if (!active && el.open) el.close();
  }, [active]);

  const close = () => setActive(null);
  const restoreFocus = () => {
    setActive(null);
    requestAnimationFrame(() => {
      if (opener.current?.isConnected) opener.current.focus({ preventScroll: true });
    });
  };
  const detail = active ? overviewDefinitions[active] : null;

  return (
    <dialog
      ref={dialog}
      className="po-overview-info-dialog"
      aria-labelledby="po-overview-info-title"
      onClose={restoreFocus}
      onClick={event => {
        if (event.target !== event.currentTarget) return;
        const box = event.currentTarget.getBoundingClientRect();
        if (event.clientX < box.left || event.clientX > box.right ||
            event.clientY < box.top || event.clientY > box.bottom) close();
      }}
    >
      <header className="po-overview-info-header">
        <div>
          <p>Product Overview · How it's counted</p>
          <h2 id="po-overview-info-title">{detail?.title ?? "Metric definition"}</h2>
        </div>
        <button type="button" className="icon-button po-overview-info-close"
          onClick={close} aria-label="Close metric explanation">
          <svg className="icon" aria-hidden="true"><use href="#i-close" /></svg>
        </button>
      </header>
      <div className="po-overview-info-body">
        <h3>Logic</h3>
        <p>{detail?.rule}</p>
        <div className="po-overview-info-example">
          <strong>Example</strong>
          <p>{detail?.example}</p>
        </div>
        {detail?.note ? <p className="po-overview-info-note">{detail.note}</p> : null}
      </div>
    </dialog>
  );
}
