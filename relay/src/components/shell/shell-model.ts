import { NAV_ITEMS, type NavItem, type NavSection } from "./nav-items";

export interface ShellBreadcrumb {
  label: string;
  href?: string;
}

export interface NavItemsGroup {
  section: NavSection;
  items: NavItem[];
}

const SHELL_SECTIONS: NavSection[] = ["core", "billing", "system"];
const ROOT_BREADCRUMB: ShellBreadcrumb = { label: "AIChat Relay", href: "/dashboard" };

export function getActiveNavItem(pathname: string | null | undefined): NavItem | null {
  if (!pathname) return null;
  return NAV_ITEMS.find((item) => pathname === item.href || pathname.startsWith(`${item.href}/`)) ?? null;
}

export function buildBreadcrumbs(pathname: string | null | undefined): ShellBreadcrumb[] {
  const activeItem = getActiveNavItem(pathname);
  const breadcrumbs = [ROOT_BREADCRUMB];
  if (activeItem) breadcrumbs.push({ label: activeItem.label });
  return breadcrumbs;
}

export function groupNavItems(items: readonly NavItem[]): NavItemsGroup[] {
  return SHELL_SECTIONS.map((section) => ({
    section,
    items: items.filter((item) => item.section === section),
  }));
}

export function isEditableShortcutTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return (
    target.tagName === "INPUT" ||
    target.tagName === "TEXTAREA" ||
    target.isContentEditable ||
    target.contentEditable === "true"
  );
}
