import { MotionConfig } from "motion/react"

import { SiteFooter } from "@/components/footer"
import { Hero } from "@/components/hero"

function App() {
  return (
    <MotionConfig reducedMotion="user">
      <div className="bg-neutral-950">
        <main>
          <Hero />
        </main>
        <SiteFooter />
      </div>
    </MotionConfig>
  )
}

export default App
