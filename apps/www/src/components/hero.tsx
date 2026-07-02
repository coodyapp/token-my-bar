import { useEffect, useRef, useState } from "react"
import { ArrowRight, Check, Copy } from "lucide-react"
import { toast } from "sonner"

import { GithubMark } from "@/components/github-mark"
import { MenubarPreview } from "@/components/menubar-preview"

const REPO = "https://github.com/coodyapp/token-my-bar"

const INSTALL_COMMANDS = [
  "brew tap coodyapp/token-my-bar https://github.com/coodyapp/token-my-bar",
  "brew install --cask token-my-bar",
]

const INSTALL_CMD = INSTALL_COMMANDS.join("\n")

export function Hero() {
  const [copied, setCopied] = useState(false)
  const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout>>(null)

  useEffect(() => {
    return () => {
      if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current)
    }
  }, [])

  const copyInstallCmd = async () => {
    await navigator.clipboard.writeText(INSTALL_CMD)
    setCopied(true)
    toast("Copied to clipboard")
    if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current)
    copiedTimeoutRef.current = setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div className="relative w-full bg-neutral-950">
      <div className="absolute top-0 z-[0] h-full w-full bg-[radial-gradient(ellipse_20%_80%_at_50%_-20%,rgba(229,72,77,0.3),rgba(255,255,255,0))]"></div>
      <section className="relative z-1 mx-auto max-w-full">
        <div className="pointer-events-none absolute h-full w-full overflow-hidden opacity-50 [perspective:200px]">
          <div className="absolute inset-0 [transform:rotateX(35deg)]">
            <div className="animate-grid [inset:0%_0px] [margin-left:-50%] [height:300vh] [width:600vw] [transform-origin:100%_0_0] [background-image:linear-gradient(to_right,rgba(255,255,255,0.25)_1px,transparent_0),linear-gradient(to_bottom,rgba(255,255,255,0.2)_1px,transparent_0)] [background-size:120px_120px] [background-repeat:repeat]"></div>
          </div>
          <div className="absolute inset-0 bg-gradient-to-t from-neutral-950 to-transparent to-90%"></div>
        </div>

        <div className="z-10 mx-auto max-w-screen-xl gap-12 px-4 py-28 text-gray-600 md:px-8">
          <div className="mx-auto max-w-3xl space-y-5 text-center">
            <a
              href="#install"
              className="group mx-auto block w-fit rounded-3xl border-[2px] border-white/5 bg-gradient-to-tr from-zinc-300/5 via-gray-400/5 to-transparent px-5 py-2 text-sm text-gray-400"
            >
              v{import.meta.env.VITE_TMB_VERSION} · Now available on Homebrew
              <ArrowRight className="ml-2 inline h-4 w-4 duration-300 group-hover:translate-x-1" />
            </a>

            <h1 className="mx-auto bg-[linear-gradient(180deg,_#FFF_0%,_rgba(255,_255,_255,_0.00)_202.08%)] bg-clip-text text-4xl tracking-tighter text-transparent md:text-6xl">
              Your AI usage,{" "}
              <span className="bg-gradient-to-r from-red-300 to-orange-200 bg-clip-text text-transparent">
                one glance away.
              </span>
            </h1>

            <p className="mx-auto max-w-2xl text-gray-300">
              TokenMyBar is a native macOS menu bar app that gives you
              real-time insight into token usage, reset windows, and plan
              limits across Claude Code, OpenAI Codex, and OpenCode.
            </p>
            <p className="text-center font-mono text-xs text-[rgba(235,235,245,0.45)]">
              Built with a privacy-first approach, it runs with zero
              telemetry.
            </p>
            <div className="items-center justify-center space-y-3 gap-x-3 sm:flex sm:space-y-0">
              <span className="relative inline-block overflow-hidden rounded-full p-[1.5px]">
                <span className="absolute inset-[-1000%] animate-[spin_2s_linear_infinite] bg-[conic-gradient(from_90deg_at_50%_50%,#FECACA_0%,#B22929_50%,#FECACA_100%)]" />
                <div className="inline-flex h-full w-full cursor-pointer items-center justify-center rounded-full bg-gray-950 text-xs font-medium text-gray-50 backdrop-blur-3xl">
                  <a
                    href={REPO}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="group inline-flex w-full items-center justify-center gap-2 rounded-full border-[1px] border-input bg-gradient-to-tr from-zinc-300/5 via-red-400/20 to-transparent px-10 py-4 text-center text-white transition-all duration-300 hover:scale-[1.03] hover:bg-transparent/90 sm:w-auto"
                  >
                    <GithubMark className="h-4 w-4 transition-transform duration-300 group-hover:-rotate-12 group-hover:scale-110" />
                    Star on GitHub
                  </a>
                </div>
              </span>
            </div>
          </div>

          {/* Install terminal */}
          <section
            id="install"
            className="mx-auto mt-20 flex max-w-4xl scroll-mt-8 flex-col gap-3 sm:mt-24"
          >
            <div className="overflow-hidden rounded-xl border border-white/10 bg-[#161618] shadow-[0_1px_0_rgba(255,255,255,0.06)_inset,0_20px_45px_-15px_rgba(0,0,0,0.7)]">
              <div className="flex items-center justify-between border-b border-white/10 bg-[#232326] py-2 pr-2 pl-4">
                <div className="flex items-center gap-3">
                  <div aria-hidden className="flex items-center gap-1.5">
                    <span className="size-2.5 rounded-full bg-[#ff5f57]" />
                    <span className="size-2.5 rounded-full bg-[#febc2e]" />
                    <span className="size-2.5 rounded-full bg-[#28c840]" />
                  </div>
                  <span className="font-mono text-xs font-medium text-gray-400">
                    Terminal — zsh
                  </span>
                </div>
                <button
                  type="button"
                  onClick={copyInstallCmd}
                  className="inline-flex h-7 items-center gap-1.5 rounded-md border border-white/10 bg-white/5 px-2.5 font-mono text-xs text-gray-300 transition-colors hover:border-white/20 hover:bg-white/10 hover:text-white"
                >
                  {copied ? (
                    <Check className="size-3.5 text-[#28c840]" />
                  ) : (
                    <Copy className="size-3.5" />
                  )}
                  {copied ? "copied" : "copy"}
                </button>
              </div>
              <div className="flex flex-col gap-2.5 bg-[#0c0c0e] p-5 text-left font-mono text-sm leading-6">
                {INSTALL_COMMANDS.map((command) => (
                  <div key={command} className="flex gap-2.5">
                    <span aria-hidden className="text-primary select-none">
                      $
                    </span>
                    <code className="break-all whitespace-pre-wrap text-gray-100">
                      {command}
                    </code>
                  </div>
                ))}
              </div>
            </div>
            <p className="text-center font-mono text-sm text-muted-foreground">
              Installs <code>TokenMyBar.app</code> via Homebrew cask. Prefer a
              DMG? Grab the{" "}
              <a
                href={`${REPO}/releases/latest`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary hover:underline"
              >
                latest release
              </a>
              .
            </p>
          </section>

          <div className="mx-auto mt-20 flex justify-center sm:mt-24">
            <MenubarPreview />
          </div>
        </div>
      </section>
    </div>
  )
}
