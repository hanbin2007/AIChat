"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import Link from "next/link";
import Box from "@mui/material/Box";
import AppBar from "@mui/material/AppBar";
import Toolbar from "@mui/material/Toolbar";
import Drawer from "@mui/material/Drawer";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Divider from "@mui/material/Divider";
import Typography from "@mui/material/Typography";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Breadcrumbs from "@mui/material/Breadcrumbs";
import { Stack } from "@/components/lib/stack";
import SearchRounded from "@mui/icons-material/SearchRounded";
import LogoutRounded from "@mui/icons-material/LogoutRounded";
import { NAV_ITEMS, SECTION_LABELS, type NavItem, type NavSection } from "./nav-items";
import { NavIcon } from "./nav-icon";
import { ColorSchemeToggle } from "./color-scheme-toggle";
import { CommandPalette } from "./command-palette";
import { useSnackbar } from "@/components/snackbar-provider";
import { usePageActions } from "./page-meta";

const RAIL_COLLAPSED = 80;
const RAIL_EXPANDED = 256;

interface Props {
  children: React.ReactNode;
}

export function AppShell({ children }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const snackbar = useSnackbar();
  const [expanded, setExpanded] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const { actions } = usePageActions();

  const currentItem = useMemo(() => {
    if (!pathname) return null;
    return (
      NAV_ITEMS.find((n) => pathname === n.href || pathname.startsWith(n.href + "/")) ?? null
    );
  }, [pathname]);

  const title = currentItem?.label ?? "AIChat Relay";

  const breadcrumb: { label: string; href?: string }[] = useMemo(() => {
    const trail: { label: string; href?: string }[] = [
      { label: "AIChat Relay", href: "/dashboard" },
    ];
    if (currentItem) trail.push({ label: currentItem.label });
    return trail;
  }, [currentItem]);

  const handleLogout = useCallback(async () => {
    try {
      const res = await fetch("/api/admin/logout", { method: "POST" });
      if (res.ok) {
        router.push("/login");
        router.refresh();
      } else {
        snackbar.push({ message: "注销失败", severity: "error" });
      }
    } catch {
      snackbar.push({ message: "网络错误", severity: "error" });
    }
  }, [router, snackbar]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setPaletteOpen(true);
        return;
      }
      if ((e.metaKey || e.ctrlKey) && /^[0-9]$/.test(e.key)) {
        const item = NAV_ITEMS.find((n) => n.shortcut === e.key);
        if (item) {
          e.preventDefault();
          router.push(item.href);
        }
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [router]);

  const sections: NavSection[] = ["core", "billing", "system"];
  const itemsBySection = sections.map((s) => ({
    section: s,
    items: NAV_ITEMS.filter((i) => i.section === s),
  }));

  const railWidth = expanded ? RAIL_EXPANDED : RAIL_COLLAPSED;

  const renderItem = (item: NavItem) => {
    const active =
      pathname === item.href ||
      pathname.startsWith(item.href + "/") ||
      (item.href === "/requests" && pathname.startsWith("/requests/"));
    const tooltip = expanded ? "" : `${item.label} · ⌘${item.shortcut}`;
    return (
      <ListItem key={item.href} disablePadding sx={{ display: "block" }}>
        <Tooltip title={tooltip} placement="right" disableInteractive>
          <ListItemButton
            component={Link}
            href={item.href}
            selected={active}
            sx={{
              minHeight: 48,
              px: 2,
              borderRadius: 1,
              mx: 1,
              my: 0.5,
              "&.Mui-selected": {
                bgcolor: "action.selected",
                color: "primary.main",
                "& .MuiListItemIcon-root": { color: "primary.main" },
              },
            }}
          >
            <ListItemIcon
              sx={{
                minWidth: 0,
                mr: expanded ? 2 : 0,
                justifyContent: "center",
                color: "text.secondary",
              }}
            >
              <NavIcon name={item.icon} />
            </ListItemIcon>
            {expanded ? (
              <>
                <ListItemText primary={item.label} />
                <Typography
                  variant="caption"
                  sx={{ color: "text.secondary", fontFamily: "var(--font-mono)" }}
                >
                  ⌘{item.shortcut}
                </Typography>
              </>
            ) : null}
          </ListItemButton>
        </Tooltip>
      </ListItem>
    );
  };

  return (
    <Box sx={{ display: "flex", minHeight: "100vh" }}>
      <Drawer
        variant="permanent"
        onMouseEnter={() => setExpanded(true)}
        onMouseLeave={() => setExpanded(false)}
        sx={{
          width: railWidth,
          flexShrink: 0,
          transition: "width 200ms cubic-bezier(0.2, 0, 0, 1)",
          "& .MuiDrawer-paper": {
            width: railWidth,
            transition: "width 200ms cubic-bezier(0.2, 0, 0, 1)",
            overflowX: "hidden",
            display: "flex",
            flexDirection: "column",
          },
        }}
      >
        <Box sx={{ p: 2, display: "flex", alignItems: "center", gap: 1.5, minHeight: 64 }}>
          <Box
            sx={{
              width: 36,
              height: 36,
              borderRadius: 1,
              bgcolor: "primary.main",
              color: "primary.contrastText",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontWeight: 700,
              fontSize: 18,
              flexShrink: 0,
            }}
          >
            R
          </Box>
          {expanded ? (
            <Box sx={{ overflow: "hidden" }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, lineHeight: 1.2 }}>
                AIChat Relay
              </Typography>
              <Typography variant="caption" color="text.secondary">
                管理控制台
              </Typography>
            </Box>
          ) : null}
        </Box>
        <Divider />

        <Box sx={{ flexGrow: 1, overflowY: "auto", overflowX: "hidden", py: 1 }}>
          {itemsBySection.map(({ section, items }) => (
            <Box key={section}>
              {expanded ? (
                <Typography
                  variant="overline"
                  sx={{
                    px: 3,
                    pt: 1.5,
                    color: "text.secondary",
                    display: "block",
                    fontSize: "0.6875rem",
                  }}
                >
                  {SECTION_LABELS[section]}
                </Typography>
              ) : (
                <Divider sx={{ my: 1, mx: 2 }} />
              )}
              <List disablePadding>{items.map(renderItem)}</List>
            </Box>
          ))}
        </Box>

        <Divider />
        <Stack direction={expanded ? "row" : "column"} sx={{ p: 1, gap: 0.5, alignItems: "center" }}>
          <ColorSchemeToggle />
          <Tooltip title="注销">
            <IconButton aria-label="注销" onClick={handleLogout}>
              <LogoutRounded />
            </IconButton>
          </Tooltip>
        </Stack>
      </Drawer>

      <Box
        sx={{
          flex: 1,
          minWidth: 0,
          display: "flex",
          flexDirection: "column",
        }}
      >
        <AppBar position="sticky">
          <Toolbar sx={{ gap: 2, minHeight: { xs: 64 } }}>
            <Box sx={{ flex: 1, minWidth: 0 }}>
              <Breadcrumbs sx={{ mb: 0.5, fontSize: "0.75rem" }}>
                {breadcrumb.map((b, i) =>
                  b.href ? (
                    <Link
                      key={i}
                      href={b.href}
                      style={{ color: "var(--mui-palette-text-secondary)" }}
                    >
                      {b.label}
                    </Link>
                  ) : (
                    <Typography key={i} variant="caption" color="text.secondary">
                      {b.label}
                    </Typography>
                  ),
                )}
              </Breadcrumbs>
              <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }} noWrap>
                {title}
              </Typography>
            </Box>
            {actions ? (
              <Stack direction="row" spacing={1} alignItems="center">
                {actions}
              </Stack>
            ) : null}
            <Tooltip title="命令面板 ⌘K">
              <IconButton aria-label="命令面板" onClick={() => setPaletteOpen(true)}>
                <SearchRounded />
              </IconButton>
            </Tooltip>
          </Toolbar>
        </AppBar>

        <Box sx={{ flex: 1, p: { xs: 2, md: 3 }, overflow: "auto" }}>{children}</Box>
      </Box>

      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} />
    </Box>
  );
}
