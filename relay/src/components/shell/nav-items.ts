export interface NavItem {
  href: string;
  label: string;
  icon: string;
  shortcut?: string;
  section?: "core" | "billing" | "system";
}

export const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", icon: "Dashboard", shortcut: "1", section: "core" },
  { href: "/requests", label: "Requests", icon: "Cable", shortcut: "2", section: "core" },
  { href: "/playground", label: "Playground", icon: "Forum", shortcut: "3", section: "core" },
  { href: "/accounts", label: "Accounts", icon: "Groups", shortcut: "4", section: "billing" },
  { href: "/billing", label: "Billing Studio", icon: "Payments", shortcut: "5", section: "billing" },
  { href: "/observability", label: "Observability", icon: "Monitoring", shortcut: "6", section: "billing" },
  { href: "/models", label: "Models", icon: "Hub", shortcut: "7", section: "system" },
  { href: "/settings", label: "Settings", icon: "Settings", shortcut: "8", section: "system" },
  { href: "/docs", label: "Docs", icon: "MenuBook", shortcut: "9", section: "system" },
  { href: "/about", label: "About", icon: "Info", shortcut: "0", section: "system" },
];
