import { MotionConfig } from "motion/react"

import { SiteFooter } from "@/components/footer"
import { Hero } from "@/components/hero"

function App() {
  return (
    <MotionConfig reducedMotion="user">
      <div className="bg-neutral-950">
        <Hero />
        <main className="mx-auto flex max-w-3xl flex-col gap-16 px-6 pt-4">
        </main>
        <SiteFooter />
      </div>
    </MotionConfig>
  )
}

export default App
