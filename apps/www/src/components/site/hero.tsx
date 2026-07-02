import { Download } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { ButtonLink } from "@/components/ui/button";
import { MenubarPreview } from "@/components/site/menubar-preview";

const RELEASES = "https://github.com/coodyapp/token-my-bar/releases/latest";

export function Hero() {
  return (
    <section className="mx-auto grid w-full max-w-6xl items-center gap-12 px-6 py-16 sm:py-24 lg:grid-cols-[1.05fr_0.95fr]">
      <div>
        <Badge className="animate-in fade-in slide-in-from-bottom-2 duration-500">
          Claude Code · OpenAI Codex · OpenCode
        </Badge>
        <h1 className="mt-5 max-w-2xl font-heading text-4xl font-semibold tracking-tight text-balance sm:text-5xl lg:text-6xl">
          Your AI usage, one glance away.
        </h1>
        <p className="mt-5 max-w-xl text-lg leading-8 text-muted-foreground">
          TokenMyBar is a native macOS menu bar app that shows live token usage,
          reset windows, and plan limits for the AI coding tools you already
          use — straight from official sources, with a local fallback.
        </p>
        <div className="mt-8 flex flex-wrap items-center gap-3">
          <ButtonLink size="lg" href={RELEASES}>
            <Download aria-hidden /> Download for macOS
          </ButtonLink>
          <ButtonLink size="lg" variant="outline" href="#install">
            Install with Homebrew
          </ButtonLink>
        </div>
        <p className="mt-4 text-sm text-muted-foreground">
          Free & open source · macOS 14+ · Apple Silicon
        </p>
      </div>
      <div className="justify-self-center lg:justify-self-end">
        <MenubarPreview />
      </div>
    </section>
  );
}
