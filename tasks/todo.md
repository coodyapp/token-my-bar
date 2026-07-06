# Fix Gatekeeper "app is damaged" for brew/DMG installs

Root cause: release.yml runs package.sh with no signing env → bundle ships with
only the linker's ad-hoc Mach-O signature, unsealed at bundle level
(`spctl: code has no resources but signature indicates they must be present`).
Quarantined + invalid signature = "damaged" verdict, no bypass. No paid Apple
Developer account for now (roadmap item), so: valid ad-hoc seal + docs/cask
workarounds.

## Tasks

- [x] package.sh: ad-hoc sign whole bundle when DEVELOPER_ID_APP unset; verify with codesign --verify --strict
- [x] Cask token-my-bar.rb: bump 1.0.5 → 1.0.6 (sha 920285c9…), rewrite caveats (--no-quarantine / xattr; drop wrong right-click advice)
- [x] docs/installation.md: brew --no-quarantine note; align unsigned-build note
- [x] docs/product-spec.md: roadmap line — Developer ID + notarization pending paid account, ad-hoc interim
- [x] Verify: run package.sh unsigned locally; codesign verify passes; quarantine xattr + spctl shows valid-signature rejection (not "damaged" resource error)

## Review

- package.sh now seals the whole bundle ad-hoc when unsigned: verified
  `flags=0x2(adhoc)`, `Info.plist entries=11`, `Sealed Resources version=2`,
  `codesign --verify --strict` passes, and with a simulated quarantine xattr
  `spctl` returns plain "rejected" (Open Anyway flow) instead of the broken-seal
  "code has no resources but signature indicates they must be present"
  ("damaged" verdict, no bypass).
- Cask bumped to 1.0.6; sha verified against the actual released DMG
  (920285c9…). Caveats now recommend `--no-quarantine` or
  `xattr -rd com.apple.quarantine`; the misleading right-click → Open advice is
  gone. "Open Anyway" intentionally omitted from caveats until a release with
  the sealed bundle ships (v1.0.6 still has the broken seal).
- Fix reaches users only with the next release (v1.0.7): tag → release.yml →
  new DMG → cask bump.
- Lesson: SwiftPM's linker-signed executable inside an unsealed .app reads as a
  *broken* signature to Gatekeeper — quarantined installs show "damaged" with
  no bypass. Always `codesign -s -` the assembled bundle even without a
  Developer ID.
