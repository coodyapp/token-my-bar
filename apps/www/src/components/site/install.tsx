import { useState } from "react";
import { Check, Copy, Download } from "lucide-react";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const BREW_COMMANDS = `brew tap coodyapp/token-my-bar https://github.com/coodyapp/token-my-bar
brew install --cask token-my-bar`;

const RELEASES = "https://github.com/coodyapp/token-my-bar/releases/latest";

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <Button
      variant="ghost"
      size="icon"
      aria-label={copied ? "Copied" : label}
      onClick={async () => {
        await navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
    >
      {copied ? <Check aria-hidden className="text-primary" /> : <Copy aria-hidden />}
      <span aria-live="polite" className="sr-only">
        {copied ? "Copied to clipboard" : ""}
      </span>
    </Button>
  );
}

export function Install() {
  return (
    <section id="install" aria-labelledby="install-heading" className="border-t">
      <div className="mx-auto w-full max-w-6xl px-6 py-16 sm:py-20">
        <h2 id="install-heading" className="font-heading text-3xl font-semibold tracking-tight">
          Install in seconds
        </h2>
        <p className="mt-3 max-w-2xl text-muted-foreground">
          No account, no onboarding. TokenMyBar reads the sessions your tools already have.
        </p>
        <div className="mt-10 grid gap-4 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>Homebrew</CardTitle>
              <CardDescription>Tap the repo, install the cask, done.</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-start justify-between gap-2 rounded-lg bg-muted p-4">
                <pre className="overflow-x-auto text-xs leading-6"><code>{BREW_COMMANDS}</code></pre>
                <CopyButton text={BREW_COMMANDS} label="Copy Homebrew commands" />
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Direct download</CardTitle>
              <CardDescription>
                Grab the DMG, drag to Applications, launch. If Gatekeeper objects, right-click → Open.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col items-start gap-4">
              <ButtonLink href={RELEASES}>
                <Download aria-hidden /> Latest release
              </ButtonLink>
              <p className="text-xs text-muted-foreground">
                macOS 14+ · checksums published with every release
              </p>
            </CardContent>
          </Card>
        </div>
      </div>
    </section>
  );
}
