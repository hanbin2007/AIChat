"use client";

import { useCallback, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import Box from "@mui/material/Box";
import { ShellNav } from "./shell-nav";
import { ShellTopBar } from "./shell-top-bar";
import { buildBreadcrumbs, getActiveNavItem } from "./shell-model";
import { useShellShortcuts } from "./use-shell-shortcuts";
import { useSnackbar } from "@/components/snackbar-provider";
import { usePageActions } from "./page-meta";

const CommandPalette = dynamic(
  () => import("./command-palette").then((mod) => mod.CommandPalette),
  { ssr: false },
);

interface Props {
  children: React.ReactNode;
}

export function AppShell({ children }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const snackbar = useSnackbar();
  const [expanded, setExpanded] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);
  const { actions } = usePageActions();

  const currentItem = useMemo(() => getActiveNavItem(pathname), [pathname]);
  const title = currentItem?.label ?? "AIChat Relay";
  const breadcrumbs = useMemo(() => buildBreadcrumbs(pathname), [pathname]);

  const handleLogout = useCallback(async () => {
    if (loggingOut) return;
    setLoggingOut(true);
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
    } finally {
      setLoggingOut(false);
    }
  }, [loggingOut, router, snackbar]);

  const openCommandPalette = useCallback(() => setPaletteOpen(true), []);
  useShellShortcuts({ router, onOpenCommandPalette: openCommandPalette });

  return (
    <Box sx={{ display: "flex", minHeight: "100dvh" }}>
      <ShellNav
        pathname={pathname}
        expanded={expanded}
        mobileOpen={mobileOpen}
        loggingOut={loggingOut}
        onExpand={setExpanded}
        onCloseMobile={() => setMobileOpen(false)}
        onLogout={handleLogout}
      />

      <Box
        sx={{
          flex: 1,
          minWidth: 0,
          display: "flex",
          flexDirection: "column",
        }}
      >
        <ShellTopBar
          title={title}
          breadcrumbs={breadcrumbs}
          actions={actions}
          onOpenMobileNav={() => setMobileOpen(true)}
          onOpenCommandPalette={openCommandPalette}
        />

        <Box sx={{ flex: 1, p: { xs: 2, md: 3 }, overflow: "auto" }}>{children}</Box>
      </Box>

      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} />
    </Box>
  );
}
