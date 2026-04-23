"use client";
import * as React from "react";
import { Card } from "@/components/m3";
import { cn } from "@/lib/cn";

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
  return (
    <Card variant="elevated" className="p-5">
      <div className="text-m3-label-m text-on-surface-variant">{label}</div>
      <div className="mt-2 flex items-baseline gap-2">
        <span className="text-m3-headline-m font-semibold text-on-surface">{value}</span>
        {delta && (
          <span
            className={cn(
              "text-m3-label-l",
              tone === "positive" && "text-primary",
              tone === "negative" && "text-error",
              tone === "neutral" && "text-on-surface-variant",
            )}
          >
            {delta}
          </span>
        )}
      </div>
      {helper && <div className="mt-1 text-m3-body-s text-on-surface-variant">{helper}</div>}
      {spark && spark.length > 1 && <Sparkline values={spark} />}
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
    <svg viewBox={`0 0 ${width} ${height}`} className="mt-3 h-10 w-full">
      <path d={d} fill="none" stroke="rgb(var(--md-sys-color-primary))" strokeWidth={1.5} />
    </svg>
  );
}
