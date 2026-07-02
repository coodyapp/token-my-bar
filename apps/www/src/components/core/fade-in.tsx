"use client"
import type { ReactNode } from "react"
import { motion, type Transition } from "motion/react"

import { cn } from "@/lib/utils"

type FadeInProps = {
  children: ReactNode
  className?: string
  delay?: number
  y?: number
  transition?: Transition
}

// Scroll-triggered reveal; MotionConfig(reducedMotion="user") in App.tsx
// disables this globally for prefers-reduced-motion users.
export function FadeIn({
  children,
  className,
  delay = 0,
  y = 16,
  transition,
}: FadeInProps) {
  return (
    <motion.div
      className={cn(className)}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={transition ?? { duration: 0.6, ease: "easeOut", delay }}
    >
      {children}
    </motion.div>
  )
}
