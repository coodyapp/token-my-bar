import { cn } from "@/lib/utils"

type TypewriterProps = {
  lines: string[]
  className?: string
  lineClassName?: string
  charDelayMs?: number
}

// Full text is always in the DOM (each char is its own span, revealed via
// CSS animation-delay) so this stays synchronously queryable in tests and
// degrades to plain text under prefers-reduced-motion, unlike a JS
// setInterval typist that starts empty.
export function Typewriter({
  lines,
  className,
  lineClassName,
  charDelayMs = 24,
}: TypewriterProps) {
  let globalIndex = 0

  return (
    <div className={className}>
      {lines.map((line) => {
        const chars = [...line]
        const startIndex = globalIndex
        globalIndex += chars.length
        return (
          <div key={line} className="flex gap-2.5">
            <span aria-hidden className="text-primary select-none">
              $
            </span>
            <code
              className={cn(
                "break-all whitespace-pre-wrap text-gray-100",
                lineClassName
              )}
            >
              {chars.map((ch, i) => (
                <span
                  key={i}
                  className="tmb-typewriter-char"
                  style={{
                    animationDelay: `${(startIndex + i) * charDelayMs}ms`,
                  }}
                >
                  {ch}
                </span>
              ))}
            </code>
          </div>
        )
      })}
      <span
        aria-hidden
        className="tmb-typewriter-caret"
        style={{ animationDelay: `${globalIndex * charDelayMs}ms` }}
      />
    </div>
  )
}
