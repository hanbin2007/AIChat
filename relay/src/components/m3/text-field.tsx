"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

export interface TextFieldProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "size"> {
  label?: string;
  supporting?: string;
  error?: string;
  leading?: string;
  trailing?: string;
  onTrailingClick?: () => void;
  variant?: "filled" | "outlined";
}

export const TextField = React.forwardRef<HTMLInputElement, TextFieldProps>(function TextField(
  { label, supporting, error, leading, trailing, onTrailingClick, variant = "outlined", className, id, ...props },
  ref,
) {
  const generatedId = React.useId();
  const inputId = id ?? generatedId;
  return (
    <div className={cn("flex w-full flex-col gap-1", className)}>
      {label && (
        <label htmlFor={inputId} className="text-m3-label-m text-on-surface-variant">
          {label}
        </label>
      )}
      <div
        className={cn(
          "flex h-12 items-center gap-2 rounded-m3-xs px-3 transition-colors duration-m3-short3",
          variant === "outlined"
            ? "border border-outline focus-within:border-primary focus-within:ring-1 focus-within:ring-primary"
            : "bg-surface-container-highest",
          error && "border-error focus-within:border-error focus-within:ring-error",
        )}
      >
        {leading && <Icon name={leading} size={20} className="text-on-surface-variant" />}
        <input
          ref={ref}
          id={inputId}
          {...props}
          className="flex-1 bg-transparent text-m3-body-l text-on-surface outline-none placeholder:text-on-surface-variant/70"
        />
        {trailing && (
          <button
            type="button"
            onClick={onTrailingClick}
            className="text-on-surface-variant hover:text-on-surface"
          >
            <Icon name={trailing} size={20} />
          </button>
        )}
      </div>
      {(supporting || error) && (
        <p className={cn("px-3 text-m3-body-s", error ? "text-error" : "text-on-surface-variant")}>
          {error ?? supporting}
        </p>
      )}
    </div>
  );
});
