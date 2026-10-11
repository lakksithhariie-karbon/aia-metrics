"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { usePathname } from "next/navigation";

const futureSections = [
  "Product",
  "AI Services",
  "Infra",
] as const;

/**
 * App-wide section navigation. Dashboard-to-dashboard switching still lives
 * in the separate Base UI dropdown at the right of the header.
 *
 * Only Overview has a destination in the current app. The remaining section
 * entries respond with an honest placeholder until routes are defined.
 */
export default function MainNavigationDrawer() {
  const pathname = usePathname();
  const onDelivery = pathname === "/delivery" || pathname.startsWith("/delivery/");
  const [open, setOpen] = useState(false);
  const [notice, setNotice] = useState("");
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);

  const close = useCallback(() => {
    setOpen(false);
    setNotice("");
  }, []);

  useEffect(() => {
    if (!open) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const focusFrame = requestAnimationFrame(() => {
      closeRef.current?.focus({ preventScroll: true });
    });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        close();
        return;
      }

      if (event.key !== "Tab" || !panelRef.current) return;

      const candidates = Array.from(
        panelRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      ).filter(element => element.tabIndex >= 0 && element.getClientRects().length > 0);

      const first = candidates[0];
      const last = candidates[candidates.length - 1];

      if (!first || !last) {
        event.preventDefault();
        return;
      }

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", onKeyDown, true);

    return () => {
      cancelAnimationFrame(focusFrame);
      document.removeEventListener("keydown", onKeyDown, true);
      document.body.style.overflow = previousOverflow;
      if (triggerRef.current?.isConnected) {
        triggerRef.current.focus({ preventScroll: true });
      }
    };
  }, [open, close]);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        className="brand-mark app-main-nav-trigger"
        aria-label="Open main navigation"
        aria-controls="app-main-navigation-drawer"
        aria-expanded={open}
        aria-haspopup="dialog"
        onClick={() => {
          setNotice("");
          setOpen(true);
        }}
      >
        {/* Supplied Phosphor-style hamburger: exact 256 x 256 path. */}
        <svg className="app-main-nav-hamburger" viewBox="0 0 256 256" aria-hidden="true" fill="currentColor">
          <path d="M224,128a8,8,0,0,1-8,8H40a8,8,0,0,1,0-16H216A8,8,0,0,1,224,128ZM40,72H216a8,8,0,0,0,0-16H40a8,8,0,0,0,0,16ZM216,184H40a8,8,0,0,0,0,16H216a8,8,0,0,0,0-16Z" />
        </svg>
      </button>

      {open && typeof document !== "undefined"
        ? createPortal(
            <div className="app-main-drawer-layer">
              <div
                className="app-main-drawer-backdrop"
                onClick={close}
                aria-hidden="true"
              />
              <aside
                id="app-main-navigation-drawer"
                ref={panelRef}
                className="app-main-drawer-panel"
                role="dialog"
                aria-modal="true"
                aria-labelledby="app-main-drawer-title"
              >
                <header className="app-main-drawer-header">
                  <div className="app-main-drawer-brand">
                    <strong>AI Accountant</strong>
                    <span className="app-main-drawer-brand-divider" aria-hidden="true" />
                    <span>{onDelivery ? "Engineering Metrics" : "Product Metrics"}</span>
                  </div>
                  <button
                    ref={closeRef}
                    type="button"
                    className="app-main-drawer-close"
                    onClick={close}
                    aria-label="Close main navigation"
                  >
                    <svg viewBox="0 0 24 24" aria-hidden="true" fill="none">
                      <path d="M5 5L19 19M19 5L5 19" />
                    </svg>
                  </button>
                </header>

                <div className="app-main-drawer-body">
                  <nav aria-label="Main sections" className="app-main-drawer-nav">
                    <h2 id="app-main-drawer-title" className="app-main-drawer-eyebrow">
                      Sections
                    </h2>
                    <div className="app-main-drawer-sections">
                      <Link
                        href="/overview"
                        className={"app-main-drawer-item" + (!onDelivery ? " is-current" : "")}
                        aria-current={!onDelivery ? "page" : undefined}
                        onClick={close}
                      >
                        Overview
                      </Link>
                      <Link
                        href="/delivery"
                        className={"app-main-drawer-item" + (onDelivery ? " is-current" : "")}
                        aria-current={onDelivery ? "page" : undefined}
                        onClick={close}
                      >
                        Engineering &amp; Delivery
                      </Link>
                      {futureSections.map(section => (
                        <button
                          type="button"
                          key={section}
                          className="app-main-drawer-item"
                          onClick={() =>
                            setNotice(section + " will be connected when its section is ready.")
                          }
                        >
                          {section}
                        </button>
                      ))}
                    </div>
                    <p className="app-main-drawer-notice" role="status" aria-live="polite">
                      {notice}
                    </p>
                  </nav>
                </div>
              </aside>
            </div>,
            document.body,
          )
        : null}
    </>
  );
}
