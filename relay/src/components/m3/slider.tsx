"use client";
import * as React from "react";
import { cn } from "@/lib/cn";

export interface SliderProps {
  value: number;
  min?: number;
  max?: number;
  step?: number;
  onChange: (value: number) => void;
  label?: string;
  valueLabel?: string;
  ticks?: number[];
  className?: string;
  disabled?: boolean;
}

export function Slider({
  value,
  min = 0,
  max = 100,
  step = 1,
  onChange,
  label,
  valueLabel,
  ticks,
  className,
  disabled,
}: SliderProps) {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <div className={cn("w-full", className)}>
      {(label || valueLabel) && (
        <div className="mb-1 flex items-center justify-between">
          {label && <span className="text-m3-label-m text-on-surface-variant">{label}</span>}
          {valueLabel && <span className="text-m3-label-l font-medium text-primary">{valueLabel}</span>}
        </div>
      )}
      <div className="relative h-10 select-none">
        <div className="absolute left-0 right-0 top-1/2 h-1 -translate-y-1/2 rounded-full bg-surface-container-highest" />
        <div
          className="absolute left-0 top-1/2 h-1 -translate-y-1/2 rounded-full bg-primary"
          style={{ width: `${pct}%` }}
        />
        {ticks?.map((tick) => {
          const tp = ((tick - min) / (max - min)) * 100;
          return (
            <span
              key={tick}
              aria-hidden
              className="absolute top-1/2 h-1 w-1 -translate-y-1/2 rounded-full bg-on-surface/40"
              style={{ left: `calc(${tp}% - 2px)` }}
            />
          );
        })}
        <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={value}
          disabled={disabled}
          onChange={(e) => onChange(Number(e.currentTarget.value))}
          className="absolute inset-0 cursor-pointer appearance-none bg-transparent [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:h-5 [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-primary [&::-webkit-slider-thumb]:shadow [&::-moz-range-thumb]:h-5 [&::-moz-range-thumb]:w-5 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-primary [&::-moz-range-thumb]:border-0"
        />
      </div>
    </div>
  );
}
