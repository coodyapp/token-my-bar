import { useEffect, useRef, useState } from "react"
import {
  Calendar,
  ChartColumn,
  CircleCheck,
  Clock,
  Code,
  LoaderCircle,
  RefreshCw,
  Settings,
  Sparkles,
  Terminal,
  type LucideIcon,
} from "lucide-react"

import { BorderTrail } from "@/components/core/border-trail"

// Faithful HTML recreation of the app popover (PopoverView.swift, dark mode).
// Vendors, rows, and percentages mirror PreviewSnapshot.swift; metrics are
// 1pt = 1px: 380px popover, 14px padding, 150×6 bars, 38px percent column.

type Row = {
  key: "session" | "weekly" | "monthly"
  title: string
  reset: string
  percent: number
}

type Vendor = { name: string; icon: LucideIcon; plan: string; rows: Row[] }

const VENDORS: Vendor[] = [
  {
    name: "OpenCode",
    icon: Code,
    plan: "Go",
    rows: [
      {
        key: "session",
        title: "Rolling Usage",
        reset: "Resets in 5h 0m",
        percent: 0,
      },
      {
        key: "weekly",
        title: "Weekly Usage",
        reset: "Resets in 6d 2h",
        percent: 80,
      },
      {
        key: "monthly",
        title: "Monthly Usage",
        reset: "Resets in 22d 20h",
        percent: 100,
      },
    ],
  },
  {
    name: "OpenAI Codex",
    icon: Terminal,
    plan: "Plus",
    rows: [
      {
        key: "session",
        title: "Session",
        reset: "Resets in 3h 2m",
        percent: 27,
      },
      {
        key: "weekly",
        title: "Weekly Usage",
        reset: "Resets in 6d 4h",
        percent: 14,
      },
      {
        key: "monthly",
        title: "Monthly Usage",
        reset: "Resets in 22d 21h",
        percent: 5,
      },
    ],
  },
  {
    name: "Claude Code",
    icon: Sparkles,
    plan: "Pro",
    rows: [
      {
        key: "session",
        title: "Session",
        reset: "Resets in 1h 12m",
        percent: 82,
      },
      {
        key: "weekly",
        title: "Weekly Usage",
        reset: "Resets in 2d 18h",
        percent: 65,
      },
      {
        key: "monthly",
        title: "Monthly Usage",
        reset: "Resets in 18d 6h",
        percent: 42,
      },
    ],
  },
]

// macOS dark palette (systemRed / systemGreen / systemYellow / systemGray).
const MAC = {
  red: "#ff453a",
  green: "#32d74b",
  yellow: "#ffd60a",
  gray: "#98989d",
  label: "rgba(255,255,255,0.9)",
  secondary: "rgba(235,235,245,0.6)",
  divider: "rgba(255,255,255,0.1)",
}

const BAR_DURATION = 700

// ProgressBar.swift: gray 0–69%, yellow 70–99%, red at 100%.
function fillColor(percent: number) {
  if (percent >= 100) return MAC.red
  if (percent >= 70) return MAC.yellow
  return MAC.gray
}

function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

/// Counts toward `target` on the same clock as the bar's width transition
/// (ease-out, BAR_DURATION, staggered delay) so number and bar move together.
function AnimatedPercent({ target, delay }: { target: number; delay: number }) {
  const [display, setDisplay] = useState(target)
  const displayRef = useRef(target)

  useEffect(() => {
    const from = displayRef.current
    if (from === target) return
    if (prefersReducedMotion()) {
      displayRef.current = target
      setDisplay(target)
      return
    }

    let raf = 0
    const start = performance.now() + delay
    const tick = (now: number) => {
      const t = Math.min(Math.max((now - start) / BAR_DURATION, 0), 1)
      const eased = 1 - Math.pow(1 - t, 3)
      const value = Math.round(from + (target - from) * eased)
      displayRef.current = value
      setDisplay(value)
      if (t < 1) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [target, delay])

  return <>{display}%</>
}

function UsageBar({
  row,
  filled,
  delay,
}: {
  row: Row
  filled: boolean
  delay: number
}) {
  const Icon = row.key === "session" ? Clock : Calendar
  const target = filled ? row.percent : 0
  return (
    <div className="flex items-center">
      <Icon
        aria-hidden
        className="size-5 shrink-0 p-[3.5px]"
        style={{ color: MAC.secondary }}
      />
      <div className="flex flex-col gap-px pl-[9px]">
        <span
          className="text-[13px] leading-4 font-medium"
          style={{ color: MAC.label }}
        >
          {row.title}
        </span>
        <span
          className="text-[11px] leading-[14px]"
          style={{ color: MAC.secondary }}
        >
          {row.reset}
        </span>
      </div>
      <div className="min-w-3 flex-1" />
      <div
        role="progressbar"
        aria-label={`${row.title} usage`}
        aria-valuenow={row.percent}
        aria-valuemin={0}
        aria-valuemax={100}
        className="h-[6px] w-[150px] shrink-0 overflow-hidden rounded-full"
        style={{ backgroundColor: "rgba(152,152,157,0.3)" }}
      >
        <div
          className="h-full rounded-full transition-[width] duration-700 ease-out motion-reduce:transition-none"
          style={{
            width: target > 0 ? `max(6px, ${target}%)` : "0px",
            backgroundColor: fillColor(row.percent),
            transitionDelay: `${delay}ms`,
          }}
        />
      </div>
      <span
        className="w-[38px] pl-2.5 text-right text-[12px] tabular-nums"
        style={{ color: MAC.secondary }}
      >
        <AnimatedPercent target={target} delay={delay} />
      </span>
    </div>
  )
}

function StatusBadge() {
  return (
    <span
      className="flex items-center gap-1 rounded-full px-[7px] py-[2.5px] text-[11px] leading-[13px] font-semibold"
      style={{
        color: MAC.green,
        backgroundColor: "rgba(50,215,75,0.14)",
        boxShadow: "inset 0 0 0 1px rgba(50,215,75,0.55)",
      }}
    >
      <CircleCheck aria-hidden className="size-[11px]" /> OK
    </span>
  )
}

/// HeaderButton.swift: 26×26, rounded 6, hover fill primary/10; while
/// loading a small spinner replaces the icon.
function HeaderButton({
  icon: Icon,
  label,
  loading = false,
  onClick,
}: {
  icon: LucideIcon
  label: string
  loading?: boolean
  onClick?: () => void
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className="flex size-[26px] items-center justify-center rounded-md transition-colors duration-150 hover:bg-white/10"
    >
      {loading ? (
        <LoaderCircle
          aria-hidden
          className="size-[13px] animate-spin motion-reduce:animate-none"
          style={{ color: MAC.secondary }}
        />
      ) : (
        <Icon
          aria-hidden
          className="size-[13px]"
          style={{ color: MAC.secondary }}
        />
      )}
    </button>
  )
}

function VendorSection({
  vendor,
  filled,
}: {
  vendor: Vendor
  filled: boolean
}) {
  const Icon = vendor.icon
  return (
    <section aria-label={vendor.name} className="px-3.5 py-3">
      <div className="flex items-center gap-2 pb-2.5">
        <Icon
          aria-hidden
          className="size-[18px] shrink-0 p-0.5"
          style={{ color: MAC.label }}
        />
        <span
          className="text-[14px] font-semibold"
          style={{ color: MAC.label }}
        >
          {vendor.name}
        </span>
        <span
          className="rounded-full px-1.5 py-0.5 text-[10px] leading-3 font-medium"
          style={{
            color: MAC.secondary,
            backgroundColor: "rgba(235,235,245,0.18)",
          }}
        >
          {vendor.plan}
        </span>
        <div className="min-w-2 flex-1" />
        <StatusBadge />
      </div>
      <div className="flex flex-col gap-2.5">
        {vendor.rows.map((row, index) => (
          <UsageBar
            key={row.key}
            row={row}
            filled={filled}
            delay={index * 90}
          />
        ))}
      </div>
    </section>
  )
}

export function MenubarPreview() {
  const [filled, setFilled] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const refreshingRef = useRef(false)
  const fillTimeoutRef = useRef<ReturnType<typeof setTimeout>>(null)
  const refreshTimeoutRef = useRef<ReturnType<typeof setTimeout>>(null)

  // Refresh like the app: spinner in the header, bars drain and re-fill.
  const runRefresh = () => {
    if (refreshingRef.current) return
    refreshingRef.current = true
    setRefreshing(true)
    setFilled(false)
    // One refresh is in flight at a time (guarded above), so a single ref
    // holds the active timeout instead of an ever-growing array.
    refreshTimeoutRef.current = setTimeout(() => {
      refreshingRef.current = false
      setRefreshing(false)
      setFilled(true)
    }, 900)
  }

  // Fill on mount, then loop the refresh simulation.
  useEffect(() => {
    fillTimeoutRef.current = setTimeout(() => setFilled(true), 300)
    const interval = setInterval(runRefresh, 7000)

    return () => {
      clearInterval(interval)
      if (fillTimeoutRef.current) clearTimeout(fillTimeoutRef.current)
      if (refreshTimeoutRef.current) clearTimeout(refreshTimeoutRef.current)
    }
  }, [])

  return (
    <figure
      aria-label="TokenMyBar popover preview"
      className="w-full max-w-[380px]"
    >
      <div
        className="relative w-[380px] max-w-full rounded-[14px] shadow-2xl"
        style={{
          backgroundColor: "rgba(44,44,46,0.88)",
          boxShadow:
            "inset 0 0 0 1px rgba(255,255,255,0.12), 0 25px 50px -12px rgba(0,0,0,0.5)",
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif',
        }}
      >
        <BorderTrail
          className="bg-gradient-to-l from-red-300 via-red-500 to-transparent"
          size={120}
          style={{
            boxShadow:
              "0px 0px 60px 30px rgb(255 69 58 / 40%), 0 0 100px 60px rgb(0 0 0 / 50%), 0 0 140px 90px rgb(0 0 0 / 50%)",
          }}
        />
        <div className="flex items-center gap-2.5 px-3.5 pt-3 pb-2.5">
          <ChartColumn
            aria-hidden
            className="size-7 shrink-0 p-1"
            strokeWidth={2.5}
            style={{ color: MAC.red }}
          />
          <div className="flex flex-col gap-px">
            <span
              className="text-[14px] leading-4 font-semibold"
              style={{ color: MAC.label }}
            >
              TokenMyBar
            </span>
            <span
              className="flex items-center gap-1 text-[11px] leading-[14px]"
              style={{ color: MAC.secondary }}
            >
              <Clock aria-hidden className="size-[11px]" />
              {refreshing ? "Updating…" : "Updated 2 min. ago"}
            </span>
          </div>
          <div className="min-w-2 flex-1" />
          <div className="flex items-center gap-0.5">
            <HeaderButton
              icon={RefreshCw}
              label={refreshing ? "Refreshing" : "Refresh"}
              loading={refreshing}
              onClick={runRefresh}
            />
            <HeaderButton icon={Settings} label="Settings" />
          </div>
        </div>

        {VENDORS.map((vendor) => (
          <div key={vendor.name}>
            <div className="h-px" style={{ backgroundColor: MAC.divider }} />
            <VendorSection vendor={vendor} filled={filled} />
          </div>
        ))}
      </div>
      <figcaption className="mt-4 text-center font-mono text-xs text-[rgba(235,235,245,0.45)]">
        Built with a privacy-first approach, it runs with zero telemetry.
      </figcaption>
    </figure>
  )
}
