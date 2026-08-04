import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vitest/config"

import { version as TMB_VERSION } from "./package.json"

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  // Mirrors vite.config.ts: without it the hero renders "vundefined" in tests.
  define: {
    "import.meta.env.VITE_TMB_VERSION": JSON.stringify(TMB_VERSION),
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    globals: true,
  },
})
