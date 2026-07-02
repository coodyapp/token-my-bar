# TokenMyBar User Guide

TokenMyBar is a native macOS menu bar app that shows AI usage from OpenCode, OpenAI Codex, and Claude Code.

## Requirements

- macOS 14 or newer
- Existing OpenCode, Codex, or Claude Code sessions on this Mac

## Menu Bar Display

Open Settings from the popover menu and choose `Display Mode`:

- `Icon + Percentage`: native vendor icon followed by usage percentage.
- `Percentage Only`: usage percentages without icons.
- `Icons Only`: compact vendor icons without labels.
- `Summary`: one calculated percentage.
- `Custom`: currently follows icon plus percentage while preserving future custom behavior.

## Plan Badges

Each vendor section shows your subscription plan next to the vendor name when
it can be determined: Claude Code (e.g. `Pro`, `Max`, `Team`), OpenAI Codex
(e.g. `Plus`), and OpenCode (`Go`).

## Vendors

Use `Vendors` to enable or disable:

- OpenCode
- Codex
- Claude

Disabled vendors are skipped during refresh and hidden from the menu bar.

## Summary Calculation

Summary mode can calculate:

- `Highest Usage`: shows the vendor with the highest known usage percent.
- `Average Usage`: shows average percent across active vendors.
- `Selected Provider`: uses the configured primary vendor when available.

## Menu Bar Behavior

- `Hide labels when space is limited`: reserved for compact menu bar behavior.
- `Collapse to summary automatically`: switches to summary when multiple vendors would take too much space.
- `Show provider order`: keeps selected primary vendor first when configured.
- `Show colored usage indicators`: lets menu bar text use accent color when monochrome is disabled.
- `Monochrome icons`: follows macOS menu bar style.
- `Use original colored icons`: reserved for vendor-branded icons.

## Refresh

- Click the refresh icon in the popover.
- Use `Command-R` while the popover is focused.
- Right-click the menu bar item and choose `Refresh`.

## Privacy

TokenMyBar reads usage from local app sessions and provider APIs using existing local credentials. It does not proxy usage through TokenMyBar servers and does not store secrets in snapshot cache.

## Troubleshooting

- If usage is missing, open the source app once and refresh TokenMyBar.
- If a vendor says `Sign in`, re-authenticate in that vendor's app.
- If the menu bar is crowded, enable `Collapse to summary automatically`.
