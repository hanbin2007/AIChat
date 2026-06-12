"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Dialog from "@mui/material/Dialog";
import DialogContent from "@mui/material/DialogContent";
import TextField from "@mui/material/TextField";
import List from "@mui/material/List";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Box from "@mui/material/Box";
import Typography from "@mui/material/Typography";
import SearchRounded from "@mui/icons-material/SearchRounded";
import { NAV_ITEMS } from "./nav-items";
import { NavIcon } from "./nav-icon";

interface Props {
  open: boolean;
  onClose: () => void;
}

export function CommandPalette({ open, onClose }: Props) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setQuery("");
      setActive(0);
      const timer = setTimeout(() => inputRef.current?.focus(), 50);
      return () => clearTimeout(timer);
    }
  }, [open]);

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return NAV_ITEMS;
    return NAV_ITEMS.filter(
      (item) =>
        item.label.toLowerCase().includes(q) ||
        item.href.toLowerCase().includes(q) ||
        item.icon.toLowerCase().includes(q),
    );
  }, [query]);

  useEffect(() => {
    setActive(0);
  }, [query]);

  const go = (href: string) => {
    onClose();
    router.push(href);
  };

  const handleKey = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((i) => Math.min(i + 1, matches.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const item = matches[active];
      if (item) go(item.href);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogContent sx={{ p: 0 }}>
        <Box sx={{ p: 2, borderBottom: 1, borderColor: "divider" }}>
          <TextField
            inputRef={inputRef}
            placeholder="搜索页面…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKey}
            fullWidth
            slotProps={{
              input: {
                startAdornment: (
                  <SearchRounded sx={{ color: "text.secondary", mr: 1 }} />
                ),
              },
            }}
          />
        </Box>
        <List sx={{ maxHeight: 360, overflow: "auto", py: 1 }}>
          {matches.length === 0 ? (
            <Box sx={{ p: 4, textAlign: "center" }}>
              <Typography color="text.secondary">没有匹配项</Typography>
            </Box>
          ) : (
            matches.map((item, i) => (
              <ListItemButton
                key={item.href}
                selected={i === active}
                onClick={() => go(item.href)}
                onMouseEnter={() => setActive(i)}
                sx={{ borderRadius: 1, mx: 1 }}
              >
                <ListItemIcon sx={{ minWidth: 36 }}>
                  <NavIcon name={item.icon} fontSize="small" />
                </ListItemIcon>
                <ListItemText
                  primary={item.label}
                  secondary={item.href}
                  slotProps={{ secondary: { sx: { fontFamily: "var(--font-mono)" } } }}
                />
                <Typography
                  variant="caption"
                  sx={{
                    fontFamily: "var(--font-mono)",
                    color: "text.secondary",
                    ml: 2,
                  }}
                >
                  ⌘{item.shortcut}
                </Typography>
              </ListItemButton>
            ))
          )}
        </List>
      </DialogContent>
    </Dialog>
  );
}
