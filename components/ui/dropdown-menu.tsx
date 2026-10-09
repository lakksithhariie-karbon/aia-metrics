"use client";

import * as React from "react";
import { Menu as MenuPrimitive } from "@base-ui/react/menu";

/**
 * shadcn/ui Base UI Dropdown Menu composition adapted to this application's
 * existing CSS system (the project does not use Tailwind).
 * https://ui.shadcn.com/docs/components/base/dropdown-menu
 *
 * Base UI handles keyboard movement, focus restoration, Escape, outside-click.
 */
export function DropdownMenu(props: MenuPrimitive.Root.Props) {
  return <MenuPrimitive.Root data-slot="dropdown-menu" {...props} />;
}

export function DropdownMenuTrigger(props: MenuPrimitive.Trigger.Props) {
  return <MenuPrimitive.Trigger data-slot="dropdown-menu-trigger" {...props} />;
}

export function DropdownMenuContent({
  align = "end",
  alignOffset = 0,
  side = "bottom",
  sideOffset = 8,
  className,
  ...props
}: MenuPrimitive.Popup.Props &
  Pick<MenuPrimitive.Positioner.Props, "align" | "alignOffset" | "side" | "sideOffset">) {
  return (
    <MenuPrimitive.Portal>
      <MenuPrimitive.Positioner
        data-slot="dropdown-menu-positioner"
        className="app-dropdown-positioner"
        align={align}
        alignOffset={alignOffset}
        side={side}
        sideOffset={sideOffset}
      >
        <MenuPrimitive.Popup
          data-slot="dropdown-menu-content"
          className={["app-dropdown-content", className].filter(Boolean).join(" ")}
          {...props}
        />
      </MenuPrimitive.Positioner>
    </MenuPrimitive.Portal>
  );
}

export function DropdownMenuGroup(props: MenuPrimitive.Group.Props) {
  return <MenuPrimitive.Group data-slot="dropdown-menu-group" {...props} />;
}

export function DropdownMenuLabel(props: MenuPrimitive.GroupLabel.Props) {
  return <MenuPrimitive.GroupLabel data-slot="dropdown-menu-label" {...props} />;
}

/** Navigation links use aria-current, not multiple radio checkmarks. */
export function DropdownMenuLinkItem(props: MenuPrimitive.LinkItem.Props) {
  return (
    <MenuPrimitive.LinkItem
      data-slot="dropdown-menu-link-item"
      closeOnClick
      {...props}
    />
  );
}

export function DropdownMenuSeparator(props: MenuPrimitive.Separator.Props) {
  return <MenuPrimitive.Separator data-slot="dropdown-menu-separator" {...props} />;
}
