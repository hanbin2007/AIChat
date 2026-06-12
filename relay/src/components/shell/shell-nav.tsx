"use client";

import Link from "next/link";
import Avatar from "@mui/material/Avatar";
import Box from "@mui/material/Box";
import Divider from "@mui/material/Divider";
import Drawer from "@mui/material/Drawer";
import IconButton from "@mui/material/IconButton";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";
import LogoutRounded from "@mui/icons-material/LogoutRounded";
import { Stack } from "@/components/lib/stack";
import { ColorSchemeToggle } from "./color-scheme-toggle";
import { NavIcon } from "./nav-icon";
import { NAV_ITEMS, SECTION_LABELS, type NavItem } from "./nav-items";
import { getActiveNavItem, groupNavItems } from "./shell-model";

export const RAIL_COLLAPSED = 80;
export const RAIL_EXPANDED = 256;
export const MOBILE_DRAWER_WIDTH = 288;

interface ShellNavProps {
  pathname: string | null;
  expanded: boolean;
  mobileOpen: boolean;
  loggingOut: boolean;
  onExpand: (expanded: boolean) => void;
  onCloseMobile: () => void;
  onLogout: () => void;
}

export function ShellNav({
  pathname,
  expanded,
  mobileOpen,
  loggingOut,
  onExpand,
  onCloseMobile,
  onLogout,
}: ShellNavProps) {
  const railWidth = expanded ? RAIL_EXPANDED : RAIL_COLLAPSED;

  return (
    <>
      <Drawer
        variant="temporary"
        open={mobileOpen}
        onClose={onCloseMobile}
        ModalProps={{ keepMounted: true }}
        sx={{
          display: { xs: "block", sm: "none" },
          "& .MuiDrawer-paper": {
            width: MOBILE_DRAWER_WIDTH,
            maxWidth: "88vw",
            overflowX: "hidden",
            display: "flex",
            flexDirection: "column",
          },
        }}
      >
        <ShellNavContent
          pathname={pathname}
          showLabels
          loggingOut={loggingOut}
          onCloseMobile={onCloseMobile}
          onLogout={onLogout}
        />
      </Drawer>

      <Drawer
        variant="permanent"
        onMouseEnter={() => onExpand(true)}
        onMouseLeave={() => onExpand(false)}
        sx={{
          display: { xs: "none", sm: "block" },
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
        <ShellNavContent
          pathname={pathname}
          showLabels={expanded}
          loggingOut={loggingOut}
          onCloseMobile={onCloseMobile}
          onLogout={onLogout}
        />
      </Drawer>
    </>
  );
}

function ShellNavContent({
  pathname,
  showLabels,
  loggingOut,
  onCloseMobile,
  onLogout,
}: {
  pathname: string | null;
  showLabels: boolean;
  loggingOut: boolean;
  onCloseMobile: () => void;
  onLogout: () => void;
}) {
  const itemsBySection = groupNavItems(NAV_ITEMS);

  return (
    <>
      <ShellBrand showLabels={showLabels} />
      <Divider />
      <Box sx={{ flexGrow: 1, overflowY: "auto", overflowX: "hidden", py: 1 }}>
        {itemsBySection.map(({ section, items }) => (
          <Box key={section}>
            {showLabels ? (
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
            <List disablePadding>
              {items.map((item) => (
                <ShellNavItem
                  key={item.href}
                  item={item}
                  pathname={pathname}
                  showLabels={showLabels}
                  onCloseMobile={onCloseMobile}
                />
              ))}
            </List>
          </Box>
        ))}
      </Box>
      <Divider />
      <Stack direction={showLabels ? "row" : "column"} sx={{ p: 1, gap: 0.5, alignItems: "center" }}>
        <ColorSchemeToggle />
        <Tooltip title="注销">
          <span>
            <IconButton aria-label="注销" onClick={onLogout} disabled={loggingOut}>
              <LogoutRounded />
            </IconButton>
          </span>
        </Tooltip>
      </Stack>
    </>
  );
}

function ShellBrand({ showLabels }: { showLabels: boolean }) {
  return (
    <Box sx={{ p: 2, display: "flex", alignItems: "center", gap: 1.5, minHeight: 64 }}>
      <Avatar
        variant="rounded"
        sx={{
          width: 36,
          height: 36,
          bgcolor: "primary.main",
          color: "primary.contrastText",
          fontWeight: 700,
          fontSize: 18,
          flexShrink: 0,
        }}
      >
        R
      </Avatar>
      {showLabels ? (
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
  );
}

function ShellNavItem({
  item,
  pathname,
  showLabels,
  onCloseMobile,
}: {
  item: NavItem;
  pathname: string | null;
  showLabels: boolean;
  onCloseMobile: () => void;
}) {
  const active = getActiveNavItem(pathname) === item;
  const tooltip = showLabels ? "" : `${item.label} · ⌘${item.shortcut}`;

  return (
    <ListItem disablePadding sx={{ display: "block" }}>
      <Tooltip title={tooltip} placement="right" disableInteractive>
        <ListItemButton
          component={Link}
          href={item.href}
          selected={Boolean(active)}
          aria-label={showLabels ? undefined : item.label}
          onClick={onCloseMobile}
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
              mr: showLabels ? 2 : 0,
              justifyContent: "center",
              color: "text.secondary",
            }}
          >
            <NavIcon name={item.icon} />
          </ListItemIcon>
          {showLabels ? (
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
}
