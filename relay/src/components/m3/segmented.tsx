"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

export interface SegmentedOption<T extends string> {
  value: T;
  label: string;
  icon?: string;
}

export function Segmented<T extends string>({
  options,
  value,
  onChange,
  className,
}: {
  options: SegmentedOption<T>[];
  value: T;
  onChange: (value: T) => void;
  className?: string;
}) {
  return (
    <div
      role="tablist"
      className={cn("inline-flex rounded-full border border-outline bg-surface", className)}
    >
      {options.map((opt, i) => {
        const active = opt.value === value;
        return (
          <button
            key={opt.value}
            role="tab"
            aria-selected={active}
            onClick={() => onChange(opt.value)}
            className={cn(
              "state-layer flex h-10 items-center gap-1 px-4 text-m3-label-l font-medium transition-colors duration-m3-short3",
              i === 0 && "rounded-l-full",
              i === options.length - 1 && "rounded-r-full",
              i > 0 && "border-l border-outline",
              active ? "bg-secondary-container text-on-secondary-container" : "text-on-surface-variant",
            )}
          >
            {active && <Icon name="check" size={16} />}
            {opt.icon && !active && <Icon name={opt.icon} size={18} />}
            <span>{opt.label}</span>
          </button>
        );
      })}
    </div>
  );
}
