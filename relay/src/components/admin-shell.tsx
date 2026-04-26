"use client";
import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { cn } from "@/lib/cn";
import { Icon, IconButton } from "@/components/m3";

export interface NavItem {
  href: string;
  label: string;
  icon: string;
  shortcut?: string;
  section?: "core" | "billing" | "system";
}

export const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", icon: "dashboard", shortcut: "1", section: "core" },
  { href: "/requests", label: "Requests", icon: "cable", shortcut: "2", section: "core" },
  { href: "/playground", label: "Playground", icon: "forum", shortcut: "3", section: "core" },
  { href: "/accounts", label: "Accounts", icon: "groups", shortcut: "4", section: "billing" },
  { href: "/billing", label: "Billing Studio", icon: "payments", shortcut: "5", section: "billing" },
  { href: "/observability", label: "Observability", icon: "monitoring", shortcut: "6", section: "billing" },
  { href: "/models", label: "Models", icon: "network_intel_node", shortcut: "7", section: "system" },
  { href: "/settings", label: "Settings", icon: "settings", shortcut: "8", section: "system" },
  { href: "/docs", label: "Docs", icon: "menu_book", shortcut: "9", section: "system" },
  { href: "/about", label: "About", icon: "info", shortcut: "0", section: "system" },
];

export function AdminShell({
  children,
  title,
  breadcrumb,
  actions,
}: {
  children: React.ReactNode;
  title: string;
  breadcrumb?: string[];
  actions?: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [railExpanded, setRailExpanded] = React.useState(false);
  const [paletteOpen, setPaletteOpen] = React.useState(false);
  const [isDark, setIsDark] = React.useState(false);

  React.useEffect(() => {
    setIsDark(document.documentElement.classList.contains("dark"));
  }, []);

  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;
      if (meta && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen(true);
        return;
      }
      if (meta && /^[0-9]$/.test(e.key)) {
        const nav = NAV_ITEMS.find((n) => n.shortcut === e.key);
        if (nav) {
          e.preventDefault();
          router.push(nav.href);
        }
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [router]);

  function toggleTheme() {
    const next = !isDark;
    setIsDark(next);
    document.documentElement.classList.toggle("dark", next);
    localStorage.setItem("relay_theme", next ? "dark" : "light");
  }

  async function logout() {
    await fetch("/api/admin/logout", { method: "POST" });
    router.push("/login");
  }

  return (
    <div className="flex min-h-screen bg-surface">
      {/* Navigation rail */}
      <aside
        className={cn(
          "sticky top-0 flex h-screen shrink-0 flex-col border-r border-outline-variant bg-surface-container-low py-4 transition-all duration-m3-medium1 ease-m3-standard",
          railExpanded ? "w-64" : "w-20",
        )}
        onMouseEnter={() => setRailExpanded(true)}
        onMouseLeave={() => setRailExpanded(false)}
      >
        <div className="mb-6 flex items-center justify-center">
          <span className="flex h-10 w-10 items-center justify-center rounded-m3-md bg-primary-container text-on-primary-container">
            <Icon name="hub" size={24} />
          </span>
        </div>
        <nav className="flex flex-1 flex-col gap-1 px-2 thin-scroll overflow-y-auto">
          {(["core", "billing", "system"] as const).map((section, i) => (
            <React.Fragment key={section}>
              {i > 0 && <div className="my-2 h-px bg-outline-variant" />}
              {NAV_ITEMS.filter((n) => n.section === section).map((item) => {
                const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={cn(
                      "state-layer flex items-center gap-3 rounded-full px-3 py-2 text-m3-label-l transition-colors duration-m3-short3",
                      active
                        ? "bg-secondary-container text-on-secondary-container"
                        : "text-on-surface-variant",
                    )}
                  >
                    <span className="flex h-8 w-8 items-center justify-center">
                      <Icon name={item.icon} size={22} filled={active} />
                    </span>
                    <span
                      className={cn(
                        "whitespace-nowrap transition-opacity duration-m3-short3",
                        railExpanded ? "opacity-100" : "opacity-0",
                      )}
                    >
                      {item.label}
                    </span>
                    {railExpanded && item.shortcut && (
                      <span className="ml-auto text-m3-label-s text-on-surface-variant">
                        ⌘{item.shortcut}
                      </span>
                    )}
                  </Link>
                );
              })}
            </React.Fragment>
          ))}
        </nav>
        <div className="mt-auto space-y-1 px-2">
          <IconButton icon={isDark ? "light_mode" : "dark_mode"} onClick={toggleTheme} aria-label="切换主题" />
          <IconButton icon="logout" onClick={logout} aria-label="注销" />
        </div>
      </aside>

      {/* Main column */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-10 flex h-16 items-center gap-3 border-b border-outline-variant bg-surface/80 px-6 backdrop-blur">
          <div className="flex flex-1 items-baseline gap-2">
            {breadcrumb?.map((segment) => (
              <React.Fragment key={segment}>
                <span className="text-m3-title-s text-on-surface-variant">{segment}</span>
                <span className="text-on-surface-variant">/</span>
              </React.Fragment>
            ))}
            <h1 className="text-m3-title-l font-medium text-on-surface">{title}</h1>
          </div>
          <button
            onClick={() => setPaletteOpen(true)}
            className="state-layer hidden h-10 min-w-64 items-center gap-3 rounded-full bg-surface-container px-4 text-m3-body-m text-on-surface-variant md:inline-flex"
          >
            <Icon name="search" size={20} />
            <span className="flex-1 text-left">全局搜索</span>
            <span className="rounded bg-surface-container-highest px-2 py-0.5 text-m3-label-s">⌘K</span>
          </button>
          {actions}
        </header>
        <main className="flex-1 overflow-auto thin-scroll">
          {children}
        </main>
      </div>

      {paletteOpen && <CommandPalette onClose={() => setPaletteOpen(false)} />}
    </div>
  );
}

function CommandPalette({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const [query, setQuery] = React.useState("");
  const inputRef = React.useRef<HTMLInputElement>(null);
  React.useEffect(() => inputRef.current?.focus(), []);
  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);
  const q = query.toLowerCase();
  const matches = NAV_ITEMS.filter((n) => n.label.toLowerCase().includes(q));
  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-scrim/40 p-4 pt-24"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xl rounded-m3-xl bg-surface-container-high p-4 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-3 border-b border-outline-variant pb-3">
          <Icon name="search" size={22} className="text-on-surface-variant" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索页面、账户、设备、请求…"
            className="flex-1 bg-transparent text-m3-body-l outline-none"
          />
          <span className="rounded bg-surface-container-highest px-2 py-0.5 text-m3-label-s text-on-surface-variant">
            Esc
          </span>
        </div>
        <ul className="mt-2 flex max-h-72 flex-col overflow-auto thin-scroll">
          {matches.map((item) => (
            <li key={item.href}>
              <button
                className="state-layer flex w-full items-center gap-3 rounded-m3-sm px-3 py-2 text-left text-m3-body-m"
                onClick={() => {
                  router.push(item.href);
                  onClose();
                }}
              >
                <Icon name={item.icon} size={22} className="text-on-surface-variant" />
                <span className="flex-1">{item.label}</span>
                <span className="text-m3-label-s text-on-surface-variant">⌘{item.shortcut}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
