import { Logo } from "@/components/site/logo";

const REPO = "https://github.com/coodyapp/token-my-bar";

export function Footer() {
  return (
    <footer className="border-t">
      <div className="mx-auto flex w-full max-w-6xl flex-col items-center justify-between gap-4 px-6 py-8 text-sm text-muted-foreground sm:flex-row">
        <Logo className="text-foreground" />
        <nav aria-label="Footer" className="flex flex-wrap items-center gap-6">
          <a className="transition-colors hover:text-foreground" href={REPO}>GitHub</a>
          <a className="transition-colors hover:text-foreground" href={`${REPO}/wiki`}>Wiki</a>
          <a className="transition-colors hover:text-foreground" href={`${REPO}/blob/main/CHANGELOG.md`}>Changelog</a>
          <a className="transition-colors hover:text-foreground" href={`${REPO}/blob/main/docs/privacy.md`}>Privacy</a>
        </nav>
        <p>MIT © 2026 coodyapp</p>
      </div>
    </footer>
  );
}
