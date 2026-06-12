import { describe, expect, it } from "vitest";
import { NAV_ITEMS, type NavItem } from "@/components/shell/nav-items";
import {
  buildBreadcrumbs,
  getActiveNavItem,
  groupNavItems,
  isEditableShortcutTarget,
} from "@/components/shell/shell-model";

describe("shell model", () => {
  describe("getActiveNavItem", () => {
    it("matches nav items by exact href", () => {
      expect(getActiveNavItem("/dashboard")).toEqual(NAV_ITEMS[0]);
      expect(getActiveNavItem("/requests")).toEqual(NAV_ITEMS[1]);
    });

    it("matches nested routes without matching href prefixes", () => {
      expect(getActiveNavItem("/requests/conversations/req_123")).toEqual(NAV_ITEMS[1]);
      expect(getActiveNavItem("/docs/reference")).toEqual(NAV_ITEMS[8]);
      expect(getActiveNavItem("/docs-preview")).toBeNull();
    });

    it("returns null when pathname is missing or unknown", () => {
      expect(getActiveNavItem(null)).toBeNull();
      expect(getActiveNavItem("")).toBeNull();
      expect(getActiveNavItem("/login")).toBeNull();
    });
  });

  describe("buildBreadcrumbs", () => {
    it("always starts with the dashboard breadcrumb", () => {
      expect(buildBreadcrumbs("/login")).toEqual([
        { label: "AIChat Relay", href: "/dashboard" },
      ]);
    });

    it("adds the active nav item as the current page", () => {
      expect(buildBreadcrumbs("/billing")).toEqual([
        { label: "AIChat Relay", href: "/dashboard" },
        { label: "计费工作室" },
      ]);
      expect(buildBreadcrumbs("/requests/conversations/req_123")).toEqual([
        { label: "AIChat Relay", href: "/dashboard" },
        { label: "请求日志" },
      ]);
    });
  });

  describe("groupNavItems", () => {
    it("groups items into the shell section order", () => {
      expect(groupNavItems(NAV_ITEMS)).toEqual([
        { section: "core", items: NAV_ITEMS.slice(0, 3) },
        { section: "billing", items: NAV_ITEMS.slice(3, 6) },
        { section: "system", items: NAV_ITEMS.slice(6) },
      ]);
    });

    it("keeps empty sections in the shell section order", () => {
      const customItems: NavItem[] = [
        {
          href: "/settings",
          label: "设置",
          icon: "Settings",
          shortcut: "8",
          section: "system",
        },
      ];

      expect(groupNavItems(customItems)).toEqual([
        { section: "core", items: [] },
        { section: "billing", items: [] },
        { section: "system", items: customItems },
      ]);
    });
  });

  describe("isEditableShortcutTarget", () => {
    it("treats text inputs, textareas, and contenteditable elements as editable", () => {
      expect(isEditableShortcutTarget(document.createElement("input"))).toBe(true);
      expect(isEditableShortcutTarget(document.createElement("textarea"))).toBe(true);

      const contentEditable = document.createElement("div");
      contentEditable.contentEditable = "true";

      expect(isEditableShortcutTarget(contentEditable)).toBe(true);
    });

    it("returns false for non-editable or missing targets", () => {
      expect(isEditableShortcutTarget(document.createElement("button"))).toBe(false);
      expect(isEditableShortcutTarget(document.createTextNode("shortcut"))).toBe(false);
      expect(isEditableShortcutTarget(null)).toBe(false);
    });
  });
});
