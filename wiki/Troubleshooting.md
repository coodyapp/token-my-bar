# Troubleshooting

| Symptom | Fix |
|---|---|
| Vendor shows **Sign in** | Authenticate once in that vendor's own app/CLI, then refresh (⌘R in the popover). |
| Claude shows no data | Approve the macOS Keychain prompt (choose *Always Allow* to stop repeats). |
| OpenCode shows no data | Log in to opencode.ai in Chrome/Chromium, or set `TOKEN_MY_BAR_OPENCODE_COOKIE`. |
| Numbers look stale | Row is marked *estimated/stale* when the official source is unreachable — usage falls back to local history. Refresh or re-auth. |
| Gatekeeper blocks the app | Right-click → Open, or allow under System Settings → Privacy & Security. |
| Crowded menu bar | Enable *Collapse to summary automatically* in Settings. |

Diagnostics CLI: `token-my-bar status --refresh --verbose` and `token-my-bar doctor`.
