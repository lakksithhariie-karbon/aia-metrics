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
    rule: "Count each distinct user with at least one independent qualifying accounting action in the last rolling 7 days. Compare with the preceding 7 days.",
    example: "A person uploads three bills and edits a transaction. That's one weekly active user, even if they work across two companies.",
  },
  mau: {
    title: "Monthly core-active users",
    rule: "Count distinct users performing the same independent core actions over the last rolling 30 days. Compare with the preceding 30 days.",
    example: "A user works on ten different days during the month. They still count as one monthly active user.",
  },
  stickiness: {
    title: "Stickiness (WAU / MAU)",
    rule: "Divide rolling 7-day core-active users by rolling 30-day core-active users. Both use identical eligibility rules and the same reporting cutoff.",
    example: "150 weekly active users out of 500 monthly active users means 30% stickiness.",
  },
  weekly: {
    title: "Weekly core-active users",
    rule: "For each of the last 12 completed IST Monday–Sunday weeks, count each qualifying user once. 'First observed' means their first recorded core-work week; 'Returning' means they had a qualifying event in an earlier recorded week.",
    example: "If 50 people worked this week and 8 were observed for the first time, the bar shows 8 first observed and 42 returning.",
    note: "First observed is not signup. Tracking was incomplete during May–July 2026.",
  },
  frequency: {
    title: "Core usage frequency",
    rule: "Look at the last 4 completed IST Monday–Sunday weeks. Put each user who did independent core work into exactly one bucket: active in 1, 2, 3, or 4 of those weeks. Divide each bucket by all users active in this four-week window.",
    example: "Someone works in week 1 and week 3 but not weeks 2 and 4. They belong in 'Exactly 2 weeks'.",
  },
  core_7d: {
    title: "7-day core adoption",
    rule: "Of companies with a recorded successful Tally/Zoho integration and a full 28-day observation window, count those doing independent accounting work within 7 days of integration.",
    example: "If 6 out of 10 eligible integrated companies do core work by day 7, adoption is 60%.",
  },
  value_28d: {
    title: "28-day value conversion",
    rule: "An eligible company must complete the sequence within 28 days: successful integration → qualifying training sync → independent core work on a later IST calendar day → another qualifying sync. Divide completed companies by the mature integration cohort.",
    example: "Integration on day 0, training sync on day 1, core work on day 2 and closing sync on day 3 qualifies.",
    note: "A single post-work sync alone is not this stricter value milestone.",
  },
  sustained_28d: {
    title: "28-day sustained adoption",
    rule: "Of the same mature integration cohort, count companies with independent core work in at least 2 of the first 4 seven-day periods after integration.",
    example: "Core work in week 1 and week 3 counts as sustained. Ten actions in week 1 alone do not.",
  },
  journey: {
    title: "Integration journey",
    rule: "Track the same mature integration cohort through successful integration → independent core work within 7 days → qualifying sync after that work, within 28 days. Next-step conversion uses the preceding stage; cumulative conversion uses all integrated companies.",
    example: "10 integrated → 6 started → 4 synced: final next-step conversion is 4/6 = 66.7%, and cumulative conversion is 4/10 = 40%.",
    note: "Module branches below the funnel can overlap; the three adoption outcomes are separate metrics.",
  },
  feature: {
    title: "Module usage over time",
    rule: "Count distinct users doing independent core work in AP/Bills, AR/Invoices or Transactions in each of the last 12 completed IST weeks. One user can count in more than one module line.",
    example: "Someone uploads bills and updates a transaction in the same week: one AP user and one Transactions user.",
  },
  mix: {
    title: "Module combinations",
    rule: "Group distinct core-active companies by their exact combination of AP, AR and Transactions over the last rolling 28 days. Each company belongs to one combination. Dots compare category shares with the preceding 28 days; the change is in percentage points.",
    example: "If 3 of 10 active companies use AP + Transactions (but not AR), that category's share is 30%.",
  },
  friction: {
    title: "Issues that need attention",
    rule: "For each workflow, incidence = distinct companies recording a failed action or explicit revert to review ÷ companies attempting that workflow in the same rolling 28 days. 'Later success' means the same company recorded that workflow succeeding after its latest failure. 'Needs review' means no such later success was observed.",
    example: "If 3 of 20 companies have a failed bill upload, incidence is 15%. If 2 later upload successfully, 1 has no observed follow-up.",
    note: "A later success does not prove the original item was fixed. Reverting to review is intentional rework, not necessarily a product error.",
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
      <footer className="po-overview-info-foot">
        All live metrics use the published Supabase snapshot and exclude internal users.
      </footer>
    </dialog>
  );
}
