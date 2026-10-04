/** Small compatibility adapter for the two existing imperative dashboards. */
export function withCustomerNavigation(markup: string): string {
  const marker = markup.indexOf('id="retention-menu-item"');
  const closing = marker < 0 ? -1 : markup.indexOf("</button>", marker);
  if (closing < 0) throw new Error("The existing dashboard menu could not be located.");
  const at = closing + "</button>".length;
  const item = `
<a href="/customer" id="companies-menu-item" class="dashboard-option" style="text-decoration:none" role="menuitemradio" aria-checked="false">
<span class="menu-option-icon"><svg class="icon" aria-hidden="true"><use href="#i-grid"></use></svg></span>
<span class="menu-option-copy"><strong>Companies</strong><small>Module usage by company and user</small></span>
</a>`;
  return markup.slice(0, at) + item + markup.slice(at);
}

/**
 * Capture only dashboard-menu keys before the old two-option handlers run.
 * Full document navigation is intentional: the prototype is not remount-safe.
 * React never renders children into the prototype-owned DOM subtree.
 */
export function installCustomerNavigation(): () => void {
  const trigger = document.getElementById("dashboard-trigger");
  const menu = document.getElementById("dashboard-menu");
  if (!trigger || !menu) return () => {};
  const options = () => Array.from(menu.querySelectorAll<HTMLElement>('[role="menuitemradio"]'));
  const close = () => { if (!menu.hidden) trigger.click(); };
  const onKey = (event: KeyboardEvent) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;
    const onTrigger = target === trigger, inMenu = menu.contains(target);
    if (onTrigger && ["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (menu.hidden) trigger.click();
      (options().find(item => item.getAttribute("aria-checked") === "true") || options()[0])?.focus();
      return;
    }
    if (!inMenu) return;
    const items = options(), index = items.indexOf(target as HTMLElement);
    const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1
      : event.key === "ArrowDown" ? (index + 1) % items.length
      : event.key === "ArrowUp" ? (index + items.length - 1) % items.length : null;
    if (next !== null) { event.preventDefault(); event.stopImmediatePropagation(); items[next]?.focus(); }
    if (event.key === " " && target instanceof HTMLAnchorElement) { event.preventDefault(); event.stopImmediatePropagation(); target.click(); }
    if (event.key === "Escape" || event.key === "Tab") {
      event.preventDefault(); event.stopImmediatePropagation(); close();
      (event.key === "Tab" && !event.shiftKey ? document.getElementById("help-button") : trigger)?.focus();
    }
  };
  const applyHash = () => {
    const item = document.getElementById(location.hash === "#retention" ? "retention-menu-item" : "po-menu-item");
    if (item?.getAttribute("aria-checked") !== "true") item?.click();
  };
  const onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target.closest("#po-menu-item, #retention-menu-item") : null;
    if (target) history.replaceState(history.state, "", location.pathname + location.search + (target.id === "retention-menu-item" ? "#retention" : ""));
  };
  document.addEventListener("keydown", onKey, true);
  document.addEventListener("click", onClick);
  window.addEventListener("hashchange", applyHash);
  applyHash();
  return () => {
    document.removeEventListener("keydown", onKey, true);
    document.removeEventListener("click", onClick);
    window.removeEventListener("hashchange", applyHash);
  };
}
