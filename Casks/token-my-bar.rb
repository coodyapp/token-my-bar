# Homebrew cask for TokenMyBar.
#
# Usage:
#   brew tap coodyapp/token-my-bar https://github.com/coodyapp/token-my-bar
#   brew install --cask token-my-bar
#
# The sha256 below must match the DMG attached to the GitHub release for
# `version` (published by .github/workflows/release.yml). Update both together.
cask "token-my-bar" do
  version "1.0.0"
  sha256 :no_check # replaced with the released DMG checksum after each release

  url "https://github.com/coodyapp/token-my-bar/releases/download/v#{version}/TokenMyBar-#{version}.dmg"
  name "TokenMyBar"
  desc "Menu bar app showing live AI token usage for Claude Code, Codex, and OpenCode"
  homepage "https://github.com/coodyapp/token-my-bar"

  depends_on macos: ">= :sonoma"

  app "TokenMyBar.app"

  zap trash: [
    "~/Library/Application Support/TokenMyBar",
  ]

  caveats <<~EOS
    Releases are currently unsigned. If Gatekeeper blocks the first launch,
    right-click TokenMyBar.app and choose Open, or allow it under
    System Settings → Privacy & Security.
  EOS
end
