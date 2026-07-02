import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { MenubarPreview } from "@/components/menubar-preview"

describe("MenubarPreview", () => {
  it("renders every vendor section with its usage rows", () => {
    render(<MenubarPreview />)

    expect(screen.getByLabelText("OpenCode")).toBeInTheDocument()
    expect(screen.getByLabelText("OpenAI Codex")).toBeInTheDocument()
    expect(screen.getByLabelText("Claude Code")).toBeInTheDocument()

    expect(screen.getAllByRole("progressbar")).toHaveLength(9)
  })

  it("exposes a refresh control", () => {
    render(<MenubarPreview />)

    expect(screen.getByRole("button", { name: /refresh/i })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: /settings/i })).toBeInTheDocument()
  })
})
