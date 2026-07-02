import fs from "fs"
import path from "path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

// Single source of truth for the version shown on the site: Casks/token-my-bar.rb.
const cask = fs.readFileSync(
  path.resolve(__dirname, "../../Casks/token-my-bar.rb"),
  "utf-8"
)
const versionMatch = cask.match(/version "([0-9]+\.[0-9]+\.[0-9]+)"/)
if (!versionMatch) {
  throw new Error("Could not find version in Casks/token-my-bar.rb")
}
const TMB_VERSION = versionMatch[1]

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  define: {
    "import.meta.env.VITE_TMB_VERSION": JSON.stringify(TMB_VERSION),
  },
})
