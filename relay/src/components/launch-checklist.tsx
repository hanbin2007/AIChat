"use client";
import * as React from "react";
import Link from "next/link";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import Box from "@mui/material/Box";
import Avatar from "@mui/material/Avatar";
import Typography from "@mui/material/Typography";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import FlagIcon from "@mui/icons-material/Flag";
import CheckIcon from "@mui/icons-material/Check";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";

export interface ChecklistItem {
  id: string;
  label: string;
  description: string;
  done: boolean;
  href?: string;
}

export function LaunchChecklist({ items }: { items: ChecklistItem[] }) {
  const allDone = items.every((i) => i.done);
  return (
    <Card sx={{ bgcolor: "action.hover" }}>
      <CardContent>
        <Box sx={{ mb: 2, display: "flex", alignItems: "center", gap: 1.5 }}>
          <Avatar
            sx={{
              width: 40,
              height: 40,
              bgcolor: allDone ? "success.light" : "warning.light",
              color: allDone ? "success.contrastText" : "warning.contrastText",
            }}
          >
            {allDone ? <CheckCircleIcon /> : <FlagIcon />}
          </Avatar>
          <Box>
            <Typography variant="subtitle1" sx={{ fontWeight: 500 }}>
              {allDone ? "Ready to serve" : "启动清单"}
            </Typography>
            <Typography variant="caption" sx={{ color: "text.secondary" }}>
              {allDone
                ? "所有关键配置已就绪"
                : `完成 ${items.filter((i) => i.done).length}/${items.length} 项即可正式上线`}
            </Typography>
          </Box>
        </Box>
        <List disablePadding>
          {items.map((item, i) => (
            <ListItem key={item.id} disablePadding>
              <ListItemButton
                component={Link}
                href={item.href ?? "#"}
                sx={{ borderRadius: 2, alignItems: "flex-start", py: 1 }}
              >
                <ListItemIcon sx={{ minWidth: 36, mt: 0.25 }}>
                  <Avatar
                    sx={{
                      width: 24,
                      height: 24,
                      fontSize: "0.75rem",
                      bgcolor: item.done ? "success.light" : "action.selected",
                      color: item.done ? "success.contrastText" : "text.secondary",
                    }}
                  >
                    {item.done ? <CheckIcon sx={{ fontSize: 14 }} /> : i + 1}
                  </Avatar>
                </ListItemIcon>
                <ListItemText
                  primary={item.label}
                  secondary={item.description}
                  primaryTypographyProps={{ variant: "body2", fontWeight: 500 }}
                  secondaryTypographyProps={{ variant: "caption" }}
                />
                {item.href && !item.done && <ArrowForwardIcon fontSize="small" color="action" />}
              </ListItemButton>
            </ListItem>
          ))}
        </List>
      </CardContent>
    </Card>
  );
}
