import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { toast } from "sonner"

import { Hero } from "@/components/hero"

vi.mock("sonner", () => ({ toast: vi.fn() }))

describe("Hero", () => {
  it("renders the install command and GitHub CTA", () => {
    render(<Hero />)

    expect(
      screen.getByRole("link", { name: /star on github/i })
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        (_, element) =>
          element?.tagName === "CODE" &&
          element.textContent === "brew install --cask token-my-bar"
      )
    ).toBeInTheDocument()
  })

  it("copies the install command to the clipboard on click", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText },
      configurable: true,
    })

    render(<Hero />)

    fireEvent.click(screen.getByRole("button", { name: /copy/i }))

    await waitFor(() =>
      expect(writeText).toHaveBeenCalledWith(
        expect.stringContaining("brew install --cask token-my-bar")
      )
    )
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /copied/i })).toBeInTheDocument()
    )
  })

  it("shows an error and stays uncopied when the clipboard write fails", async () => {
    const writeText = vi.fn().mockRejectedValue(new Error("denied"))
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText },
      configurable: true,
    })

    render(<Hero />)

    fireEvent.click(screen.getByRole("button", { name: /copy/i }))

    await waitFor(() =>
      expect(toast).toHaveBeenCalledWith(expect.stringMatching(/fail/i))
    )
    expect(
      screen.queryByRole("button", { name: /copied/i })
    ).not.toBeInTheDocument()
  })
})
