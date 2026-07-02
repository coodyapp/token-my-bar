import { Clock3, RefreshCw } from "lucide-react";
import { Badge } from "@/components/ui/badge";

type Row = { title: string; percent: number; reset: string };
type Vendor = { name: string; plan: string; auth: string; rows: Row[] };

const vendors: Vendor[] = [
  {
    name: "Claude Code",
    plan: "Pro",
    auth: "Claude OAuth",
    rows: [
      { title: "Session", percent: 61, reset: "Resets in 59m" },
      { title: "Weekly", percent: 6, reset: "Resets in 2d 15h" },
    ],
  },
  {
    name: "OpenAI Codex",
    plan: "Plus",
    auth: "Codex OAuth",
    rows: [
      { title: "Session", percent: 1, reset: "Resets in 4h 59m" },
      { title: "Weekly", percent: 0, reset: "Resets in 6d 23h" },
    ],
  },
  {
    name: "OpenCode",
    plan: "Go",
    auth: "OpenCode cookie",
    rows: [
      { title: "Rolling", percent: 0, reset: "Resets in 5h 0m" },
      { title: "Weekly", percent: 15, reset: "Resets in 3d 21h" },
    ],
  },
];

function UsageBar({ title, percent, reset }: Row) {
  return (
    <div className="grid grid-cols-[80px_1fr_auto] items-center gap-3 text-sm">
      <span className="font-medium">{title}</span>
      <div
        role="progressbar"
        aria-label={`${title} usage`}
        aria-valuenow={percent}
        aria-valuemin={0}
        aria-valuemax={100}
        className="h-1.5 overflow-hidden rounded-full bg-muted"
      >
        <div className="h-full rounded-full bg-primary" style={{ width: `${Math.max(percent, 2)}%` }} />
      </div>
      <span className="text-xs text-muted-foreground">
        {percent}% · {reset}
      </span>
    </div>
  );
}

export function MenubarPreview() {
  return (
    <figure aria-label="TokenMyBar popover preview" className="w-full max-w-md">
      <div className="rounded-2xl border bg-popover text-popover-foreground shadow-xl">
        <div className="flex items-center justify-between border-b px-5 py-4">
          <div className="font-heading font-semibold">TokenMyBar</div>
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Clock3 aria-hidden className="size-3.5" /> Updated just now
            <RefreshCw aria-hidden className="size-3.5" />
          </div>
        </div>
        <div className="space-y-5 px-5 py-4">
          {vendors.map((vendor) => (
            <section key={vendor.name} aria-label={vendor.name} className="space-y-2.5">
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold">{vendor.name}</span>
                <Badge variant="secondary">{vendor.plan}</Badge>
                <span className="ml-auto text-xs text-muted-foreground">{vendor.auth}</span>
              </div>
              {vendor.rows.map((row) => (
                <UsageBar key={row.title} {...row} />
              ))}
            </section>
          ))}
        </div>
      </div>
      <figcaption className="mt-3 text-center text-xs text-muted-foreground">
        Live numbers from your own sessions — nothing leaves your Mac.
      </figcaption>
    </figure>
  );
}
