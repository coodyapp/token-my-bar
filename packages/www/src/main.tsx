import React from "react";
import ReactDOM from "react-dom/client";
import { BarChart3, Clock3, Code2, MoreHorizontal, RefreshCw, ShieldCheck, Sparkles, Terminal } from "lucide-react";
import "./styles.css";

const pillars = [
  {
    icon: BarChart3,
    title: "Native menu bar",
    body: "Vendor icons and usage percentages render like a macOS status item.",
  },
  {
    icon: ShieldCheck,
    title: "Local first",
    body: "Reads existing sessions on your Mac and avoids secret storage in cache.",
  },
  {
    icon: Sparkles,
    title: "Configurable display",
    body: "Choose icon plus percentage, summary, percentage-only, or icons-only.",
  },
];

const vendors = [
  { icon: Code2, name: "OpenCode", auth: "OpenCode cookie", rows: [["Rolling Usage", "0% used", "Resets in 5h 0m", 2], ["Weekly Usage", "8% used", "Resets in 6d 4h", 8], ["Monthly Usage", "6% used", "Resets in 22d 21h", 6]] },
  { icon: Terminal, name: "OpenAI Codex", auth: "Codex OAuth", plan: "Plus", rows: [["Session", "27% used", "Resets in 3h 2m", 27], ["Weekly Usage", "14% used", "Resets in 6d 4h", 14], ["Monthly Usage", "5% used", "Resets in 22d 21h", 5]] },
];

function App() {
  return (
    <main className="min-h-screen overflow-hidden bg-background text-foreground">
      <section className="mx-auto flex min-h-screen w-full max-w-6xl flex-col px-6 py-10 sm:px-10 lg:px-12">
        <nav className="flex items-center justify-between text-sm text-muted-foreground">
          <span className="font-semibold text-foreground">TokenMyBar</span>
          <span className="rounded-full border border-border/70 bg-white/5 px-3 py-1">macOS 14+</span>
        </nav>

        <div className="grid flex-1 items-center gap-12 py-20 lg:grid-cols-[1.1fr_0.9fr]">
          <div>
            <p className="mb-5 inline-flex rounded-full border border-border/70 bg-white/5 px-3 py-1 text-sm text-muted-foreground backdrop-blur">
              OpenCode · Codex · Claude
            </p>
            <h1 className="max-w-3xl text-5xl font-semibold tracking-tight sm:text-6xl lg:text-7xl">
              Native AI usage in your Mac menu bar.
            </h1>
            <p className="mt-6 max-w-2xl text-lg leading-8 text-muted-foreground">
              TokenMyBar shows vendor icons, percentages, reset windows, and summaries using a macOS-native popover and status item.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <a className="rounded-full bg-primary px-5 py-3 text-sm font-medium text-primary-foreground" href="/docs/user-guide.md">
                Read user guide
              </a>
              <a className="rounded-full border border-border px-5 py-3 text-sm font-medium" href="https://github.com/coodyapp/token-my-bar">
                GitHub
              </a>
            </div>
          </div>

          <div className="rounded-[1.375rem] border border-border bg-popover/85 shadow-2xl shadow-black/40 backdrop-blur-2xl">
            <div className="flex items-center gap-4 border-b border-border px-6 py-5">
              <BarChart3 className="h-9 w-9 text-red-400" />
              <div>
                <div className="text-[17px] font-bold">TokenMyBar</div>
                <div className="mt-1 flex items-center gap-2 text-[13px] font-semibold text-muted-foreground">
                  <Clock3 className="h-3.5 w-3.5" /> Updated 4 min ago
                </div>
              </div>
              <div className="ml-auto flex items-center gap-5 text-muted-foreground">
                <RefreshCw className="h-5 w-5" />
                <MoreHorizontal className="h-6 w-6" />
              </div>
            </div>
            <div className="space-y-5 px-6 py-5">
              {vendors.map((vendor) => (
                <section key={vendor.name} className="border-b border-border pb-5 last:border-0 last:pb-0">
                  <div className="mb-3 flex items-center gap-3">
                    <vendor.icon className="h-6 w-6" />
                    <div className="text-[17px] font-bold">{vendor.name}</div>
                    {vendor.plan ? <span className="text-[13px] font-semibold text-muted-foreground">{vendor.plan}</span> : null}
                    <span className="ml-auto rounded-full bg-emerald-500/15 px-3 py-1 text-sm font-bold text-emerald-400">OK</span>
                  </div>
                  <div className="mb-4 pl-9 text-sm font-semibold text-muted-foreground">{vendor.auth}</div>
                  <div className="space-y-4">
                    {vendor.rows.map(([title, used, reset, width]) => (
                      <div key={title} className="grid grid-cols-[26px_88px_1fr_116px] items-center gap-x-3 gap-y-2">
                        <Clock3 className="h-4 w-4 text-muted-foreground" />
                        <div className="col-span-3 text-[15px] font-bold">{title}</div>
                        <div />
                        <div className="text-sm font-semibold text-muted-foreground">{used}</div>
                        <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
                          <div className="h-full rounded-full bg-red-400" style={{ width: `${width}%` }} />
                        </div>
                        <div className="text-right text-sm font-semibold text-muted-foreground">{reset}</div>
                      </div>
                    ))}
                  </div>
                </section>
              ))}
            </div>
            <div className="flex items-center gap-3 border-t border-border px-6 py-4 text-sm font-semibold text-muted-foreground">
              Usage resets follow each vendor&apos;s schedule.
              <button className="ml-auto rounded-lg bg-white/10 px-4 py-2 text-foreground">Manage Tokens…</button>
            </div>
          </div>
        </div>

        <div className="grid gap-4 pb-10 md:grid-cols-3">
          {pillars.map((pillar) => (
            <article key={pillar.title} className="rounded-3xl border border-border bg-white/5 p-6 backdrop-blur">
              <pillar.icon className="h-5 w-5 text-red-400" />
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
