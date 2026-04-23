import * as React from "react";
import { cn } from "@/lib/cn";

type Variant = "elevated" | "filled" | "outlined";

const CLASSES: Record<Variant, string> = {
  elevated: "bg-surface-container-low shadow-sm",
  filled: "bg-surface-container-highest",
  outlined: "bg-surface border border-outline-variant",
};

export function Card({
  variant = "outlined",
  className,
  children,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & { variant?: Variant }) {
  return (
    <div
      className={cn(
        "rounded-m3-md text-on-surface transition-shadow duration-m3-short3",
        CLASSES[variant],
        className,
      )}
      {...props}
    >
      {children}
    </div>
  );
}

export function CardHeader({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("px-6 pt-5 pb-2", className)} {...props}>
      {children}
    </div>
  );
}

export function CardTitle({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("text-m3-title-m font-medium text-on-surface", className)} {...props}>
      {children}
    </div>
  );
}

export function CardDescription({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("mt-1 text-m3-body-s text-on-surface-variant", className)} {...props}>
      {children}
    </div>
  );
}

export function CardContent({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("px-6 pb-5", className)} {...props}>
      {children}
    </div>
  );
}
