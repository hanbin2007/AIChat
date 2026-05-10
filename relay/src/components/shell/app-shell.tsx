"use client";
import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useColorScheme } from "@mui/material/styles";
import AppBar from "@mui/material/AppBar";
import Toolbar from "@mui/material/Toolbar";
import Drawer from "@mui/material/Drawer";
import Box from "@mui/material/Box";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Divider from "@mui/material/Divider";
import Typography from "@mui/material/Typography";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Button from "@mui/material/Button";
import LightModeIcon from "@mui/icons-material/LightMode";
import DarkModeIcon from "@mui/icons-material/DarkMode";
import LogoutIcon from "@mui/icons-material/Logout";
import SearchIcon from "@mui/icons-material/Search";
import HubIcon from "@mui/icons-material/Hub";
import { NAV_ITEMS } from "./nav-items";
import { NavIcon } from "./nav-icon";
import { CommandPalette } from "./command-palette";

const RAIL_COLLAPSED = 80;
const RAIL_EXPANDED = 256;

export function AppShell({
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
  const { mode, setMode } = useColorScheme();
  const [railExpanded, setRailExpanded] = React.useState(false);
  const [paletteOpen, setPaletteOpen] = React.useState(false);

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
    setMode(mode === "dark" ? "light" : "dark");
  }

  async function logout() {
    await fetch("/api/admin/logout", { method: "POST" });
    router.push("/login");
  }

  const railWidth = railExpanded ? RAIL_EXPANDED : RAIL_COLLAPSED;
  const isDark = mode === "dark";

  return (
    <Box sx={{ display: "flex", minHeight: "100vh", bgcolor: "background.default" }}>
      <Drawer
        variant="permanent"
        onMouseEnter={() => setRailExpanded(true)}
        onMouseLeave={() => setRailExpanded(false)}
        sx={{
          width: railWidth,
          flexShrink: 0,
          transition: (theme) =>
            theme.transitions.create("width", { duration: theme.transitions.duration.short }),
          "& .MuiDrawer-paper": {
            width: railWidth,
            boxSizing: "border-box",
            bgcolor: "background.paper",
            borderRight: 1,
            borderColor: "divider",
            overflowX: "hidden",
            transition: (theme) =>
              theme.transitions.create("width", { duration: theme.transitions.duration.short }),
          },
        }}
      >
        <Toolbar sx={{ minHeight: 64, justifyContent: "center" }}>
          <Box
            sx={{
              width: 40,
              height: 40,
              borderRadius: 2,
              bgcolor: "primary.main",
              color: "primary.contrastText",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <HubIcon />
          </Box>
        </Toolbar>
        <Box sx={{ flex: 1, overflowY: "auto", overflowX: "hidden", px: 1 }}>
          {(["core", "billing", "system"] as const).map((section, i) => (
            <React.Fragment key={section}>
              {i > 0 && <Divider sx={{ my: 1 }} />}
              <List dense disablePadding>
                {NAV_ITEMS.filter((n) => n.section === section).map((item) => {
                  const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
                  const button = (
                    <ListItemButton
                      component={Link}
                      href={item.href}
                      selected={active}
                      sx={{
                        borderRadius: 999,
                        mb: 0.5,
                        py: 1,
                        "&.Mui-selected": {
                          bgcolor: "secondary.main",
                          color: "secondary.contrastText",
                          "& .MuiListItemIcon-root": { color: "secondary.contrastText" },
                          "&:hover": { bgcolor: "secondary.main" },
                        },
                      }}
                    >
                      <ListItemIcon sx={{ minWidth: 40, justifyContent: "center" }}>
                        <NavIcon name={item.icon} />
                      </ListItemIcon>
                      <ListItemText
                        primary={item.label}
                        primaryTypographyProps={{ variant: "body2", fontWeight: 500 }}
                        sx={{
                          opacity: railExpanded ? 1 : 0,
                          transition: "opacity 150ms",
                          whiteSpace: "nowrap",
                        }}
                      />
                      {railExpanded && item.shortcut && (
                        <Typography variant="caption" sx={{ color: "text.secondary", ml: 1 }}>
                          ⌘{item.shortcut}
                        </Typography>
                      )}
                    </ListItemButton>
                  );
                  return (
                    <ListItem key={item.href} disablePadding>
                      {railExpanded ? (
                        button
                      ) : (
                        <Tooltip title={item.label} placement="right">
                          {button}
                        </Tooltip>
                      )}
                    </ListItem>
                  );
                })}
              </List>
            </React.Fragment>
          ))}
        </Box>
        <Box sx={{ p: 1, display: "flex", flexDirection: "column", gap: 0.5 }}>
          <Tooltip title="切换主题" placement="right">
            <IconButton onClick={toggleTheme} aria-label="切换主题">
              {isDark ? <LightModeIcon /> : <DarkModeIcon />}
            </IconButton>
          </Tooltip>
          <Tooltip title="注销" placement="right">
            <IconButton onClick={logout} aria-label="注销">
              <LogoutIcon />
            </IconButton>
          </Tooltip>
        </Box>
      </Drawer>

      <Box sx={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
        <AppBar
          position="sticky"
          sx={{
            bgcolor: "background.default",
            backdropFilter: "blur(8px)",
            zIndex: (theme) => theme.zIndex.appBar,
          }}
        >
          <Toolbar sx={{ gap: 1 }}>
            <Box sx={{ flex: 1, display: "flex", alignItems: "baseline", gap: 1 }}>
              {breadcrumb?.map((segment) => (
                <React.Fragment key={segment}>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    {segment}
                  </Typography>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    /
                  </Typography>
                </React.Fragment>
              ))}
              <Typography variant="h6" component="h1" sx={{ fontWeight: 500 }}>
                {title}
              </Typography>
            </Box>
            <Button
              onClick={() => setPaletteOpen(true)}
              variant="text"
              color="inherit"
              startIcon={<SearchIcon />}
              sx={{
                display: { xs: "none", md: "inline-flex" },
                bgcolor: "action.hover",
                borderRadius: 999,
                color: "text.secondary",
                minWidth: 256,
                justifyContent: "flex-start",
                px: 2,
                "&:hover": { bgcolor: "action.selected" },
              }}
              endIcon={
                <Typography
                  variant="caption"
                  sx={{
                    bgcolor: "action.selected",
                    px: 0.75,
                    py: 0.25,
                    borderRadius: 0.5,
                  }}
                >
                  ⌘K
                </Typography>
              }
            >
              <Box component="span" sx={{ flex: 1, textAlign: "left" }}>
                全局搜索
              </Box>
            </Button>
            {actions}
          </Toolbar>
        </AppBar>
        <Box component="main" sx={{ flex: 1, overflow: "auto" }}>
          {children}
        </Box>
      </Box>
      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} />
    </Box>
  );
}
