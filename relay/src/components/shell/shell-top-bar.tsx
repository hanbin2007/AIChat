"use client";

import Link from "next/link";
import AppBar from "@mui/material/AppBar";
import Breadcrumbs from "@mui/material/Breadcrumbs";
import Box from "@mui/material/Box";
import IconButton from "@mui/material/IconButton";
import Toolbar from "@mui/material/Toolbar";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";
import MenuRounded from "@mui/icons-material/MenuRounded";
import SearchRounded from "@mui/icons-material/SearchRounded";
import { Stack } from "@/components/lib/stack";
import type { ShellBreadcrumb } from "./shell-model";

interface ShellTopBarProps {
  title: string;
  breadcrumbs: ShellBreadcrumb[];
  actions: React.ReactNode | null;
  onOpenMobileNav: () => void;
  onOpenCommandPalette: () => void;
}

export function ShellTopBar({
  title,
  breadcrumbs,
  actions,
  onOpenMobileNav,
  onOpenCommandPalette,
}: ShellTopBarProps) {
  return (
    <AppBar position="sticky">
      <Toolbar sx={{ gap: 2, minHeight: { xs: 64 } }}>
        <IconButton
          aria-label="打开导航"
          edge="start"
          onClick={onOpenMobileNav}
          sx={{ display: { xs: "inline-flex", sm: "none" } }}
        >
          <MenuRounded />
        </IconButton>
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Breadcrumbs sx={{ mb: 0.5, fontSize: "0.75rem" }}>
            {breadcrumbs.map((item, index) =>
              item.href ? (
                <Link
                  key={`${item.href}-${index}`}
                  href={item.href}
                  style={{ color: "var(--mui-palette-text-secondary)" }}
                >
                  {item.label}
                </Link>
              ) : (
                <Typography key={`${item.label}-${index}`} variant="caption" color="text.secondary">
                  {item.label}
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
          <IconButton aria-label="命令面板" onClick={onOpenCommandPalette}>
            <SearchRounded />
          </IconButton>
        </Tooltip>
      </Toolbar>
    </AppBar>
  );
}
