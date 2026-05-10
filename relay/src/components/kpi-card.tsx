"use client";
import * as React from "react";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import Typography from "@mui/material/Typography";
import Box from "@mui/material/Box";

export function KpiCard({
  label,
  value,
  delta,
  helper,
  spark,
  tone = "neutral",
}: {
  label: string;
  value: string;
  delta?: string;
  helper?: string;
  spark?: number[];
  tone?: "neutral" | "positive" | "negative";
}) {
  const deltaColor =
    tone === "positive" ? "primary.main" : tone === "negative" ? "error.main" : "text.secondary";
  return (
    <Card>
      <CardContent>
        <Typography variant="overline" sx={{ color: "text.secondary" }}>
          {label}
        </Typography>
        <Box sx={{ mt: 1, display: "flex", alignItems: "baseline", gap: 1 }}>
          <Typography variant="h4" sx={{ fontWeight: 600 }}>
            {value}
          </Typography>
          {delta && (
            <Typography variant="body2" sx={{ color: deltaColor, fontWeight: 500 }}>
              {delta}
            </Typography>
          )}
        </Box>
        {helper && (
          <Typography variant="caption" sx={{ color: "text.secondary", display: "block", mt: 0.5 }}>
            {helper}
          </Typography>
        )}
        {spark && spark.length > 1 && <Sparkline values={spark} />}
      </CardContent>
    </Card>
  );
}

function Sparkline({ values }: { values: number[] }) {
  const max = Math.max(...values, 1);
  const width = 200;
  const height = 40;
  const step = values.length > 1 ? width / (values.length - 1) : 0;
  const d = values
    .map((v, i) => {
      const x = i * step;
      const y = height - (v / max) * height;
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(" ");
  return (
    <Box sx={{ mt: 1.5, height: 40, width: "100%" }}>
      <svg viewBox={`0 0 ${width} ${height}`} width="100%" height="100%" preserveAspectRatio="none">
        <path d={d} fill="none" stroke="var(--mui-palette-primary-main)" strokeWidth={1.5} />
      </svg>
    </Box>
  );
}
