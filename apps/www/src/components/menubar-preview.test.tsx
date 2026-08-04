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

    // OpenCode 3 windows, Codex 2, Claude 3, Antigravity 1 group — the billed
    // spend row carries a figure but no meter, so it adds none.
    expect(screen.getAllByRole("progressbar")).toHaveLength(9)
    expect(screen.getByText("Billed API spend")).toBeInTheDocument()
    expect(screen.getByText("$21.40")).toBeInTheDocument()
    expect(screen.getByText("Gemini models")).toBeInTheDocument()
    expect(screen.getByText("Max 5x")).toBeInTheDocument()
  })

  it("exposes a refresh control", () => {
    render(<MenubarPreview />)

    expect(screen.getByRole("button", { name: /refresh/i })).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /settings/i })
    ).toBeInTheDocument()
  })
})
