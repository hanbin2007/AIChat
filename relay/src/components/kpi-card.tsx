"use client";

import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import Box from "@mui/material/Box";
import Typography from "@mui/material/Typography";
import { Stack } from "@/components/lib/stack";

interface Props {
  label: string;
  value: string | number;
  delta?: { tone: "positive" | "negative" | "neutral"; text: string };
  helper?: string;
  sparkline?: number[];
}

export function KpiCard({ label, value, delta, helper, sparkline }: Props) {
  const deltaColor =
    delta?.tone === "positive"
      ? "success.main"
      : delta?.tone === "negative"
        ? "error.main"
        : "text.secondary";

  return (
    <Card sx={{ height: "100%" }}>
      <CardContent>
        <Typography
          variant="overline"
          sx={{ color: "text.secondary", display: "block", lineHeight: 1.4 }}
        >
          {label}
        </Typography>
        <Stack direction="row" alignItems="baseline" spacing={1} sx={{ mt: 0.5 }}>
          <Typography
            variant="h4"
            sx={{ fontFamily: "var(--font-mono)", fontWeight: 700 }}
          >
            {value}
          </Typography>
          {delta ? (
            <Typography
              variant="caption"
              sx={{ color: deltaColor, fontFamily: "var(--font-mono)" }}
            >
              {delta.text}
            </Typography>
          ) : null}
        </Stack>
        {helper ? (
          <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 0.5 }}>
            {helper}
          </Typography>
        ) : null}
        {sparkline && sparkline.length > 1 ? <Sparkline values={sparkline} /> : null}
      </CardContent>
    </Card>
  );
}

function Sparkline({ values }: { values: number[] }) {
  const w = 220;
  const h = 36;
  const max = Math.max(...values, 1);
  const min = Math.min(...values, 0);
  const range = Math.max(max - min, 1);
  const step = w / (values.length - 1);
  const pts = values
    .map((v, i) => {
      const x = i * step;
      const y = h - ((v - min) / range) * h;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  return (
    <Box sx={{ mt: 1.5, height: h }}>
      <svg width="100%" height={h} viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none">
        <polyline
          fill="none"
          stroke="var(--mui-palette-primary-main)"
          strokeWidth={1.5}
          strokeLinejoin="round"
          strokeLinecap="round"
          points={pts}
        />
      </svg>
    </Box>
  );
}
