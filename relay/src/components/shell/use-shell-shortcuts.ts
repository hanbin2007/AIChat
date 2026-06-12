"use client";

import { useEffect } from "react";
import type { AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { NAV_ITEMS } from "./nav-items";
import { isEditableShortcutTarget } from "./shell-model";

export function useShellShortcuts({
  router,
  onOpenCommandPalette,
}: {
  router: AppRouterInstance;
  onOpenCommandPalette: () => void;
}) {
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (isEditableShortcutTarget(event.target)) return;
      if ((event.metaKey || event.ctrlKey) && event.key === "k") {
        event.preventDefault();
        onOpenCommandPalette();
        return;
      }
      if ((event.metaKey || event.ctrlKey) && /^[0-9]$/.test(event.key)) {
        const item = NAV_ITEMS.find((navItem) => navItem.shortcut === event.key);
        if (item) {
          event.preventDefault();
          router.push(item.href);
        }
      }
    };

    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onOpenCommandPalette, router]);
}
