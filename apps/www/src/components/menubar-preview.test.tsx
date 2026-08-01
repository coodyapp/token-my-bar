import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { MenubarPreview } from "@/components/menubar-preview"

describe("MenubarPreview", () => {
  it("renders every vendor section with its usage rows", () => {
    render(<MenubarPreview />)

    expect(screen.getByLabelText("OpenCode")).toBeInTheDocument()
    expect(screen.getByLabelText("OpenAI Codex")).toBeInTheDocument()
    expect(screen.getByLabelText("Claude Code")).toBeInTheDocument()
    expect(screen.getByLabelText("Antigravity")).toBeInTheDocument()

    // Three windows each for the first three vendors, one row per model for
    // Antigravity.
    expect(screen.getAllByRole("progressbar")).toHaveLength(11)
  })

  it("exposes a refresh control", () => {
    render(<MenubarPreview />)

    expect(screen.getByRole("button", { name: /refresh/i })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: /settings/i })).toBeInTheDocument()
  })
})
