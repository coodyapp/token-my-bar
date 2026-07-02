import { Gauge } from "lucide-react";
import { cn } from "@/lib/utils";

export function Logo({ className, animated = false }: { className?: string; animated?: boolean }) {
  return (
    <span className={cn("inline-flex items-center gap-2 font-heading font-semibold", className)}>
      <Gauge aria-hidden className={cn("size-5 text-primary", animated && "animate-logo")} />
      TokenMyBar
    </span>
  );
}
