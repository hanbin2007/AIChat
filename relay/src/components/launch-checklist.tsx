"use client";

import Link from "next/link";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemButton from "@mui/material/ListItemButton";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Avatar from "@mui/material/Avatar";
import Box from "@mui/material/Box";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import CheckRounded from "@mui/icons-material/CheckRounded";
import CheckCircleRounded from "@mui/icons-material/CheckCircleRounded";
import FlagRounded from "@mui/icons-material/FlagRounded";

export interface ChecklistItem {
  id: string;
  label: string;
  helper?: string;
  done: boolean;
  href?: string;
}

interface Props {
  items: ChecklistItem[];
}

export function LaunchChecklist({ items }: Props) {
  const doneCount = items.filter((i) => i.done).length;
  const allDone = doneCount === items.length;
  const Icon = allDone ? CheckCircleRounded : FlagRounded;

  return (
    <Card>
      <CardHeader
        avatar={
          <Avatar
            sx={{
              bgcolor: allDone ? "success.main" : "primary.main",
              color: "primary.contrastText",
            }}
          >
            <Icon />
          </Avatar>
        }
        title={
          <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
            就绪清单
          </Typography>
        }
        subheader={
          <Typography variant="caption" color="text.secondary">
            {doneCount} / {items.length} 已完成
          </Typography>
        }
      />
      <CardContent sx={{ pt: 0 }}>
        <List disablePadding>
          {items.map((item, i) => {
            const content = (
              <>
                <ListItemIcon sx={{ minWidth: 44 }}>
                  <Avatar
                    sx={{
                      width: 28,
                      height: 28,
                      fontSize: 14,
                      bgcolor: item.done ? "success.main" : "action.hover",
                      color: item.done ? "primary.contrastText" : "text.primary",
                    }}
                  >
                    {item.done ? <CheckRounded fontSize="small" /> : i + 1}
                  </Avatar>
                </ListItemIcon>
                <ListItemText
                  primary={
                    <Stack direction="row" spacing={1} alignItems="baseline">
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {item.label}
                      </Typography>
                    </Stack>
                  }
                  secondary={
                    item.helper ? (
                      <Typography variant="caption" color="text.secondary">
                        {item.helper}
                      </Typography>
                    ) : undefined
                  }
                />
              </>
            );

            return (
              <ListItem key={item.id} disablePadding>
                {item.href ? (
                  <ListItemButton component={Link} href={item.href} sx={{ borderRadius: 1, py: 1 }}>
                    {content}
                  </ListItemButton>
                ) : (
                  <Box sx={{ display: "flex", alignItems: "center", width: "100%", px: 2, py: 1 }}>
                    {content}
                  </Box>
                )}
              </ListItem>
            );
          })}
        </List>
      </CardContent>
    </Card>
  );
}
