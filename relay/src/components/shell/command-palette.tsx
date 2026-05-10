"use client";
import * as React from "react";
import { useRouter } from "next/navigation";
import Dialog from "@mui/material/Dialog";
import DialogContent from "@mui/material/DialogContent";
import TextField from "@mui/material/TextField";
import InputAdornment from "@mui/material/InputAdornment";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Typography from "@mui/material/Typography";
import Box from "@mui/material/Box";
import SearchIcon from "@mui/icons-material/Search";
import { NAV_ITEMS } from "./nav-items";
import { NavIcon } from "./nav-icon";

export function CommandPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const router = useRouter();
  const [query, setQuery] = React.useState("");

  React.useEffect(() => {
    if (!open) setQuery("");
  }, [open]);

  const q = query.toLowerCase();
  const matches = NAV_ITEMS.filter((n) => n.label.toLowerCase().includes(q));

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm" scroll="paper">
      <Box sx={{ p: 2, pb: 1 }}>
        <TextField
          autoFocus
          fullWidth
          placeholder="搜索页面、账户、设备、请求…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          variant="standard"
          InputProps={{
            disableUnderline: true,
            startAdornment: (
              <InputAdornment position="start">
                <SearchIcon color="action" />
              </InputAdornment>
            ),
            endAdornment: (
              <InputAdornment position="end">
                <Typography variant="caption" sx={{ color: "text.secondary" }}>
                  Esc
                </Typography>
              </InputAdornment>
            ),
          }}
        />
      </Box>
      <DialogContent sx={{ p: 0, pb: 1 }}>
        <List dense>
          {matches.map((item) => (
            <ListItem key={item.href} disablePadding>
              <ListItemButton
                onClick={() => {
                  router.push(item.href);
                  onClose();
                }}
              >
                <ListItemIcon sx={{ minWidth: 40 }}>
                  <NavIcon name={item.icon} fontSize="small" />
                </ListItemIcon>
                <ListItemText primary={item.label} />
                {item.shortcut && (
                  <Typography variant="caption" sx={{ color: "text.secondary" }}>
                    ⌘{item.shortcut}
                  </Typography>
                )}
              </ListItemButton>
            </ListItem>
          ))}
        </List>
      </DialogContent>
    </Dialog>
  );
}
