"use client";

import React, { useEffect, useId, useRef, useState } from "react";

export interface CompactSelectOption<T extends string> {
  value: T;
  label: string;
}

function Chevron() {
  return (
    <svg className="icon compact-menu-select-chevron" viewBox="0 0 24 24" aria-hidden="true">
      <path d="m7 10 5 5 5-5" />
    </svg>
  );
}

function Check() {
  return (
    <svg className="icon compact-menu-select-check" viewBox="0 0 24 24" aria-hidden="true">
      <path d="m5 12 4 4L19 6" />
    </svg>
  );
}

export default function CompactMenuSelect<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
  className = "",
}: {
  value: T;
  options: readonly CompactSelectOption<T>[];
  onChange: (value: T) => void;
  ariaLabel: string;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(
    Math.max(0, options.findIndex(option => option.value === value)),
  );
  const rootRef = useRef<HTMLDivElement | null>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const listId = useId();
  const selected = options.find(option => option.value === value) ?? options[0];

  useEffect(() => {
    setActiveIndex(
      Math.max(0, options.findIndex(option => option.value === value)),
    );
  }, [value, options]);

  useEffect(() => {
    if (!open) return;

    const onPointerDown = (event: PointerEvent) => {
      if (
        rootRef.current &&
        event.target instanceof Node &&
        !rootRef.current.contains(event.target)
      ) {
        setOpen(false);
      }
    };

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        setOpen(false);
        rootRef.current?.querySelector<HTMLButtonElement>(
          ".compact-menu-select-trigger",
        )?.focus();
        return;
      }

      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      event.preventDefault();
      setActiveIndex(index => {
        const next =
          event.key === "ArrowDown"
            ? (index + 1) % options.length
            : (index - 1 + options.length) % options.length;
        requestAnimationFrame(() => optionRefs.current[next]?.focus());
        return next;
      });
    };

    document.addEventListener("pointerdown", onPointerDown, true);
    document.addEventListener("keydown", onKeyDown, true);
    requestAnimationFrame(() => optionRefs.current[activeIndex]?.focus());

    return () => {
      document.removeEventListener("pointerdown", onPointerDown, true);
      document.removeEventListener("keydown", onKeyDown, true);
    };
  }, [open, activeIndex, options.length]);

  const choose = (option: CompactSelectOption<T>) => {
    onChange(option.value);
    setOpen(false);
    requestAnimationFrame(() =>
      rootRef.current
        ?.querySelector<HTMLButtonElement>(".compact-menu-select-trigger")
        ?.focus(),
    );
  };

  return (
    <div
      ref={rootRef}
      className={"compact-menu-select " + className}
    >
      <button
        type="button"
        className="ui-control compact-menu-select-trigger"
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => setOpen(current => !current)}
        onKeyDown={event => {
          if (
            !open &&
            (event.key === "ArrowDown" ||
              event.key === "ArrowUp" ||
              event.key === "Enter" ||
              event.key === " ")
          ) {
            event.preventDefault();
            setOpen(true);
          }
        }}
      >
        <span>{selected?.label}</span>
        <Chevron />
      </button>

      <div
        id={listId}
        className="ui-menu-surface compact-menu-select-menu"
        role="listbox"
        aria-label={ariaLabel}
        hidden={!open}
      >
        {options.map((option, index) => {
          const current = option.value === value;
          return (
            <button
              key={option.value}
              ref={node => {
                optionRefs.current[index] = node;
              }}
              type="button"
              role="option"
              aria-selected={current}
              className={
                "compact-menu-select-option " +
                (current ? "is-selected" : "")
              }
              onMouseEnter={() => setActiveIndex(index)}
              onClick={() => choose(option)}
            >
              <span>{option.label}</span>
              {current ? <Check /> : null}
            </button>
          );
        })}
      </div>
    </div>
  );
}
