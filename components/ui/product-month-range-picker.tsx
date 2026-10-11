"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { CSSProperties, KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { completedPreset, monthLabel, rangeLabel, validMonthRange } from "../../lib/infra/date-range";
import type { MonthPreset, MonthRange } from "../../lib/infra/date-range";

function Icon({ name, className = "" }: { name: "calendar" | "down" | "check" | "close" | "left" | "right" | "info" | "arrow"; className?: string }) {
  const paths = { calendar: "M4 5h16v15H4zM4 9h16M8 3v4M16 3v4", down: "m7 10 5 5 5-5", check: "m5 12 4 4L19 6", close: "M6 6l12 12M18 6L6 18", left: "m14 6-6 6 6 6", right: "m10 6 6 6-6 6", info: "M12 11v6M12 7v.1", arrow: "M4 12h15m-5-5 5 5-5 5" };
  return <svg className={"icon " + className} viewBox="0 0 24 24" aria-hidden="true">{name === "info" ? <circle cx="12" cy="12" r="9" /> : null}<path d={paths[name]} /></svg>;
}

/** React adapter for Product's existing date-popover DOM and global CSS. */
export default function ProductMonthRangePicker({ value, asOf, firstMonth, onApply }: {
  value: MonthRange; asOf: string; firstMonth: string; onApply: (range: MonthRange) => void;
}) {
  const latest = asOf.slice(0, 7);
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<MonthRange>(value);
  const [year, setYear] = useState(Number(latest.slice(0, 4)));
  const [editing, setEditing] = useState<"start" | "end" | null>(null);
  const [position, setPosition] = useState<CSSProperties>({ right: 24, top: 100 });
  const trigger = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const minYear = Number(firstMonth.slice(0, 4));
  const maxYear = Number(latest.slice(0, 4));
  const close = useCallback(() => {
    setOpen(false);
    requestAnimationFrame(() => trigger.current?.focus({ preventScroll: true }));
  }, []);

  useEffect(() => {
    if (!open) return;
    const place = () => {
      const anchor = trigger.current?.getBoundingClientRect();
      if (!anchor) return;
      const width = Math.min(window.innerWidth <= 620 ? 414 : 586, window.innerWidth - 24);
      const height = Math.min(panel.current?.getBoundingClientRect().height || 560, window.innerHeight - 24);
      setPosition({ width, maxHeight: window.innerHeight - 24,
        left: Math.max(12, Math.min(anchor.right - width, window.innerWidth - width - 12)),
        top: Math.max(12, Math.min(anchor.bottom + 8, window.innerHeight - height - 12)),
      });
    };
    const frame = requestAnimationFrame(() => {
      place();
      panel.current?.querySelector<HTMLButtonElement>('.date-preset[aria-pressed="true"]')?.focus({ preventScroll: true });
    });
    const outside = (e: PointerEvent) => {
      if (e.target instanceof Node && !panel.current?.contains(e.target) && !trigger.current?.contains(e.target)) close();
    };
    const keydown = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); return; }
      if (e.key !== "Tab") return;
      const buttons = Array.from(panel.current?.querySelectorAll<HTMLButtonElement>('button:not([disabled])') || []);
      if (!buttons.length) return;
      const first = buttons[0], last = buttons[buttons.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    window.addEventListener("resize", place);
    document.addEventListener("pointerdown", outside, true);
    document.addEventListener("keydown", keydown, true);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("resize", place);
      document.removeEventListener("pointerdown", outside, true);
      document.removeEventListener("keydown", keydown, true);
    };
  }, [open, close]);

  const presets: { key: MonthPreset; label: string; caption: string }[] = [
    { key: "lifetime", label: "Lifetime", caption: "All available data" },
    ...(["3", "6", "12"] as const).map(key => ({ key, label: "Last " + key + " months", caption: rangeLabel(completedPreset(key, asOf)) })),
    { key: "custom", label: "Custom range", caption: "Select one or more months" },
  ];
  const choosePreset = (key: MonthPreset) => {
    if (key === "custom") { setDraft(previous => ({ ...previous, preset: "custom" })); setEditing("start"); return; }
    const next = completedPreset(key, asOf);
    setDraft(next); setEditing(null);
    setYear(Math.max(minYear, Number((next.end || latest).slice(0, 4))));
  };
  const chooseMonth = (month: string) => {
    if (editing === "end" && draft.start) {
      setDraft({ preset: "custom", start: month < draft.start ? month : draft.start, end: month < draft.start ? draft.start : month });
      setEditing(null);
    } else {
      setDraft({ preset: "custom", start: month, end: month });
      setEditing("end");
    }
  };
  const monthKeys = (e: KeyboardEvent<HTMLButtonElement>, index: number) => {
    const delta = ({ ArrowLeft: -1, ArrowRight: 1, ArrowUp: -3, ArrowDown: 3 } as Record<string, number>)[e.key];
    if (delta === undefined) return;
    e.preventDefault();
    const buttons = panel.current?.querySelectorAll<HTMLButtonElement>(".month-button");
    const target = buttons?.[index + delta];
    if (target && !target.disabled) target.focus();
  };
  const launch = () => {
    if (open) { close(); return; }
    setDraft(value); setEditing(null);
    setYear(Math.max(minYear, Number((value.end || latest).slice(0, 4))));
    setOpen(true);
  };

  return <>
    <div className="global-controls">
      <span className="global-control-label">Date range</span>
      <button ref={trigger} id="date-range-trigger" className="ui-control date-trigger" type="button"
        aria-label={"Date range, " + rangeLabel(value)} aria-haspopup="dialog"
        aria-controls="date-range-popover" aria-expanded={open} onClick={launch}>
        <Icon name="calendar" /><span id="date-range-value">{rangeLabel(value)}</span><Icon name="down" className="chevron" />
      </button>
    </div>
    {open && typeof document !== "undefined" ? createPortal(
      <div ref={panel} id="date-range-popover" className="date-popover ui-menu-surface" role="dialog"
        aria-labelledby="date-picker-title" aria-describedby="date-picker-instructions" style={position}>
        <div className="date-popover-heading"><div><h2 id="date-picker-title">Date range</h2><span>Point-in-time reporting</span></div>
          <button type="button" className="icon-button" aria-label="Close date range picker" onClick={close}><Icon name="close" /></button></div>
        <div className="date-picker-body">
          <div className="date-presets" role="group" aria-label="Date range presets">
            {presets.map(p => <button key={p.key} type="button" className="date-preset" data-preset={p.key}
              aria-pressed={draft.preset === p.key} onClick={() => choosePreset(p.key)}>
              <span><strong>{p.label}</strong><small>{p.caption}</small></span><Icon name="check" className="preset-check" />
            </button>)}
            <p className="preset-footnote">Presets use completed calendar months.</p>
          </div>
          <div className="month-picker">
            <div className="range-fields">
              <button className={"range-field" + (editing === "start" ? " is-picking" : "")} type="button" onClick={() => { setDraft(d => ({ ...d, preset: "custom" })); setEditing("start"); }}>
                <span>Start month</span><strong>{draft.preset === "lifetime" ? "All time" : draft.start ? monthLabel(draft.start) : "Choose month"}</strong>
              </button><Icon name="arrow" />
              <button className={"range-field" + (editing === "end" ? " is-picking" : "")} type="button" onClick={() => { setDraft(d => ({ ...d, preset: "custom" })); setEditing("end"); }}>
                <span>End month</span><strong>{draft.preset === "lifetime" ? "Present" : draft.end ? monthLabel(draft.end) : "Choose month"}</strong>
              </button>
            </div>
            <div className="month-picker-header"><strong>{year}</strong><div>
              <button type="button" className="icon-button" aria-label="Previous year" disabled={year <= minYear} onClick={() => setYear(y => y - 1)}><Icon name="left" /></button>
              <button type="button" className="icon-button" aria-label="Next year" disabled={year >= maxYear} onClick={() => setYear(y => y + 1)}><Icon name="right" /></button>
            </div></div>
            <div className="month-grid" role="group" aria-label="Select months">
              {Array.from({ length: 12 }, (_, i) => {
                const key = year + "-" + String(i + 1).padStart(2, "0");
                const selected = draft.preset !== "lifetime" && !!draft.start && !!draft.end && key >= draft.start && key <= draft.end;
                const endpoint = selected && (key === draft.start || key === draft.end);
                return <button key={key} type="button" data-month={key} disabled={key < firstMonth || key > latest}
                  className={"month-button" + (selected ? " in-range" : "") + (endpoint ? " is-endpoint" : "") + (key === latest ? " is-current" : "")}
                  aria-label={monthLabel(key)} aria-pressed={selected} onClick={() => chooseMonth(key)} onKeyDown={e => monthKeys(e, i)}>
                  {monthLabel(key).split(" ")[0]}
                </button>;
              })}
            </div>
            <p id="date-picker-instructions" className="month-picker-instructions">{editing === "end" ? "Choose an end month, or Apply to use just this month." : "Choose a preset or select months for a custom range."}</p>
          </div>
        </div>
        <div className="date-scope-note"><Icon name="info" /><span>End month selects the KPI and breakdown month. Start month limits the cost trend. Captured observations begin {monthLabel(firstMonth)}.</span></div>
        <div className="date-picker-footer"><span>{draft.preset === "lifetime" ? "All available data" : rangeLabel(draft)}{draft.end === latest ? <span className="partial-period">Current month is partial</span> : null}</span>
          <div><button className="ui-control" type="button" onClick={close}>Cancel</button>
            <button className="ui-control ui-primary" type="button" disabled={!validMonthRange(draft, latest)} onClick={() => { onApply(draft); close(); }}>Apply</button></div>
        </div>
      </div>, document.body) : null}
  </>;
}
