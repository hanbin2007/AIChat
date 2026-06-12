export type NavSection = "core" | "billing" | "system";

export interface NavItem {
  href: string;
  label: string;
  icon: string;
  shortcut: string;
  section: NavSection;
}

export const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "概览", icon: "Dashboard", shortcut: "1", section: "core" },
  { href: "/requests", label: "请求日志", icon: "Cable", shortcut: "2", section: "core" },
  { href: "/playground", label: "Playground", icon: "Forum", shortcut: "3", section: "core" },
  { href: "/accounts", label: "账户", icon: "Group", shortcut: "4", section: "billing" },
  { href: "/billing", label: "计费工作室", icon: "Payments", shortcut: "5", section: "billing" },
  { href: "/observability", label: "可观测性", icon: "QueryStats", shortcut: "6", section: "billing" },
  { href: "/models", label: "模型", icon: "AutoAwesome", shortcut: "7", section: "system" },
  { href: "/settings", label: "设置", icon: "Settings", shortcut: "8", section: "system" },
  { href: "/docs", label: "API 文档", icon: "MenuBook", shortcut: "9", section: "system" },
  { href: "/about", label: "关于", icon: "Info", shortcut: "0", section: "system" },
];

export const SECTION_LABELS: Record<NavSection, string> = {
  core: "核心",
  billing: "计费",
  system: "系统",
};
