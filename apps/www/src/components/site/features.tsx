import { BadgeCheck, Gauge, HardDrive, LayoutTemplate, ShieldCheck, TerminalSquare } from "lucide-react";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const features = [
  {
    icon: Gauge,
    title: "Native menu bar",
    body: "A real macOS status item and popover — vendor icons, percentages, and reset timers that feel like part of the system.",
  },
  {
    icon: BadgeCheck,
    title: "Plan aware",
    body: "Shows your actual subscription next to each vendor: Claude Pro/Max/Team, Codex Plus, OpenCode Go.",
  },
  {
    icon: HardDrive,
    title: "Official + local fallback",
    body: "Reads official usage APIs first. When they're unreachable, falls back to your local session history and marks it as estimated.",
  },
  {
    icon: ShieldCheck,
    title: "Private by design",
    body: "Uses credentials your tools already stored, behind the macOS Keychain consent prompt. Tokens are never logged or cached.",
  },
  {
    icon: LayoutTemplate,
    title: "Your bar, your rules",
    body: "Icon + percent, percent only, icons only, or one summary number. Collapse automatically when space runs out.",
  },
  {
    icon: TerminalSquare,
    title: "CLI included",
    body: "token-my-bar status --json emits a Waybar-compatible payload for scripts, tmux, and dashboards.",
  },
];

export function Features() {
  return (
    <section id="features" aria-labelledby="features-heading" className="border-t bg-muted/40">
      <div className="mx-auto w-full max-w-6xl px-6 py-16 sm:py-20">
        <h2 id="features-heading" className="font-heading text-3xl font-semibold tracking-tight">
          Built for people who live in the terminal
        </h2>
        <p className="mt-3 max-w-2xl text-muted-foreground">
          Stop tab-switching to three dashboards to see how much runway you have left.
        </p>
        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {features.map(({ icon: Icon, title, body }) => (
            <Card key={title} className="bg-card/60">
              <CardHeader>
                <Icon aria-hidden className="mb-2 size-5 text-primary" />
                <CardTitle>{title}</CardTitle>
                <CardDescription>{body}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
