import React from "react";
import ReactDOM from "react-dom/client";
import { Activity, Lock, MonitorUp } from "lucide-react";
import "./styles.css";

const pillars = [
  {
    icon: Activity,
    title: "Near-live usage",
    body: "Codex, Claude Code, and OpenCode token usage in one menu bar item.",
  },
  {
    icon: Lock,
    title: "Local first",
    body: "No cloud account, zero telemetry, no browser cookies in MVP.",
  },
  {
    icon: MonitorUp,
    title: "Native macOS",
    body: "Swift menu bar app built for low idle CPU, fast launch, and simple installs.",
  },
];

function App() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <section className="mx-auto flex min-h-screen w-full max-w-6xl flex-col px-6 py-10 sm:px-10 lg:px-12">
        <nav className="flex items-center justify-between text-sm text-muted-foreground">
          <span className="font-semibold text-foreground">TokenMyBar</span>
          <span>macOS 14+</span>
        </nav>

        <div className="grid flex-1 items-center gap-12 py-20 lg:grid-cols-[1.1fr_0.9fr]">
          <div>
            <p className="mb-5 inline-flex rounded-full border border-border px-3 py-1 text-sm text-muted-foreground">
              OpenAI Codex · Claude Code · OpenCode
            </p>
            <h1 className="max-w-3xl text-5xl font-semibold tracking-tight sm:text-6xl lg:text-7xl">
              Your AI token usage, always in your Mac menu bar.
            </h1>
            <p className="mt-6 max-w-2xl text-lg leading-8 text-muted-foreground">
              TokenMyBar does one thing perfectly: it turns your live AI token usage into a single, glanceable application right in your Mac&apos;s menu bar.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <a className="rounded-full bg-primary px-5 py-3 text-sm font-medium text-primary-foreground" href="/docs/ideia.md">
                Read project idea
              </a>
              <a className="rounded-full border border-border px-5 py-3 text-sm font-medium" href="https://github.com/">
                GitHub soon
              </a>
            </div>
          </div>

          <div className="rounded-[2rem] border border-border bg-white/60 p-5 shadow-2xl shadow-black/10 backdrop-blur dark:bg-white/5">
            <div className="rounded-[1.5rem] bg-zinc-950 p-4 text-white">
              <div className="mb-5 flex h-7 items-center gap-2 rounded-full bg-zinc-900 px-3 text-sm text-zinc-300">
                <span className="h-2 w-2 rounded-full bg-emerald-400" />
                12% | 18% | 9%
              </div>
              <div className="space-y-3">
                {['OpenAI Codex', 'Claude Code', 'OpenCode'].map((vendor, index) => (
                  <div key={vendor} className="rounded-2xl bg-zinc-900 p-4">
                    <div className="flex items-center justify-between text-sm">
                      <span>{vendor}</span>
                      <span className="text-zinc-400">{['local', 'local', 'local'][index]}</span>
                    </div>
                    <div className="mt-3 h-2 rounded-full bg-zinc-800">
                      <div className="h-2 rounded-full bg-emerald-400/40" style={{ width: `${[12, 18, 9][index]}%` }} />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div className="grid gap-4 pb-10 md:grid-cols-3">
          {pillars.map((pillar) => (
            <article key={pillar.title} className="rounded-3xl border border-border bg-white/60 p-6 dark:bg-white/5">
              <pillar.icon className="h-5 w-5" />
              <h2 className="mt-4 font-semibold">{pillar.title}</h2>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">{pillar.body}</p>
            </article>
          ))}
        </div>
      </section>
    </main>
  );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
