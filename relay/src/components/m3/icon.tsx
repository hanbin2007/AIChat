import { cn } from "@/lib/cn";

export function Icon({
  name,
  className,
  filled,
  size,
}: {
  name: string;
  className?: string;
  filled?: boolean;
  size?: number;
}) {
  return (
    <span
      className={cn("material-symbols-rounded select-none", className)}
      style={{
        fontSize: size ? `${size}px` : undefined,
        fontVariationSettings: filled ? '"FILL" 1' : '"FILL" 0',
      }}
      aria-hidden
    >
      {name}
    </span>
  );
}
