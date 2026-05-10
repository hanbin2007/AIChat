"use client";
import * as React from "react";
import Link from "next/link";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
import Divider from "@mui/material/Divider";
import Grid from "@mui/material/Grid2";
import MuiLink from "@mui/material/Link";
import PsychologyIcon from "@mui/icons-material/Psychology";
import TravelExploreIcon from "@mui/icons-material/TravelExplore";
import CodeIcon from "@mui/icons-material/Code";
import HeadphonesIcon from "@mui/icons-material/Headphones";
import ImageIcon from "@mui/icons-material/Image";
import { AppShell } from "@/components/shell/app-shell";
import { DEFAULT_MODELS } from "@/lib/gemini/models";

const CAPABILITY_META: Record<string, { Icon: React.ComponentType<{ fontSize?: "small" | "inherit" }>; label: string }> = {
  thinking: { Icon: PsychologyIcon, label: "Thinking" },
  search: { Icon: TravelExploreIcon, label: "Search" },
  codeExecution: { Icon: CodeIcon, label: "Code" },
  audio: { Icon: HeadphonesIcon, label: "Audio" },
  vision: { Icon: ImageIcon, label: "Vision" },
};

export default function ModelsPage() {
  return (
    <AppShell title="Models" breadcrumb={["Relay"]}>
      <Box sx={{ p: 3 }}>
        <Grid container spacing={2}>
          {DEFAULT_MODELS.map((m) => (
            <Grid key={m.id} size={{ xs: 12, md: 6, xl: 4 }}>
              <Card sx={{ height: "100%" }}>
                <CardContent>
                  <Typography variant="h6">{m.displayName}</Typography>
                  <Typography variant="caption" sx={{ fontFamily: "monospace", color: "text.secondary", display: "block", mt: 0.5 }}>
                    {m.id}
                  </Typography>
                  <Typography variant="caption" sx={{ color: "text.secondary", display: "block" }}>
                    family: {m.family}
                  </Typography>
                  <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mt: 2 }}>
                    {Object.entries(m.capabilities).map(([k, enabled]) => {
                      if (!enabled) return null;
                      const meta = CAPABILITY_META[k];
                      if (!meta) return null;
                      const { Icon, label } = meta;
                      return (
                        <Chip
                          key={k}
                          size="small"
                          variant="outlined"
                          icon={<Icon fontSize="small" />}
                          label={label}
                        />
                      );
                    })}
                  </Stack>
                  <Box sx={{ mt: 2 }}>
                    <Typography variant="caption" sx={{ color: "text.secondary" }}>
                      支持的思考强度
                    </Typography>
                    <Stack direction="row" spacing={1} sx={{ mt: 0.5 }} flexWrap="wrap" useFlexGap>
                      {m.supportedIntensities.map((i) => (
                        <Chip key={i} size="small" label={i} />
                      ))}
                    </Stack>
                  </Box>
                  <Divider sx={{ my: 2 }} />
                  <MuiLink component={Link} href="/billing" variant="body2" underline="hover">
                    在 Billing Studio 中编辑计价 →
                  </MuiLink>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      </Box>
    </AppShell>
  );
}
