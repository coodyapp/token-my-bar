# Developer ID Signing and Notarization

TokenMyBar releases are currently **ad-hoc signed and not notarized** — there is
no Apple Developer account yet. `install.sh` and the Homebrew cask clear the
quarantine flag so the app still opens, but a browser-downloaded DMG shows the
"unverified developer" flow.

The pipeline is already wired for the real thing. `Scripts/package.sh` signs with
a hardened runtime, notarizes, and staples whenever the credentials below are
present, and `.github/workflows/release.yml` passes them through. Until the
secrets exist they arrive as empty strings and every step takes the same ad-hoc
path it takes today, so **adding the secrets is the only change needed** — no
code edits, no workflow edits.

## What to buy

An [Apple Developer Program](https://developer.apple.com/programs/) membership,
$99/year. An individual account is enough; TokenMyBar does not need an
organization.

## One-time setup

### 1. Create the Developer ID Application certificate

In Xcode: **Settings → Accounts → (your account) → Manage Certificates → + →
Developer ID Application**. Or generate a CSR and request it at
[developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates).

Then export it **with its private key** as a `.p12`:

1. Open **Keychain Access → login → My Certificates**.
2. Right-click the `Developer ID Application: … (TEAMID)` entry → **Export**.
3. Save as `.p12` and set a strong password — this becomes
   `DEVELOPER_ID_CERT_PASSWORD`.

Base64-encode it for GitHub (the secret must be a single line):

```bash
base64 -i DeveloperID.p12 | pbcopy
```

### 2. Create an app-specific password for notarytool

At [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security →
App-Specific Passwords**, generate one named e.g. `TokenMyBar notarytool`. This
is `AC_PASSWORD`. Your regular Apple ID password will not work.

Find your team ID at
[developer.apple.com/account](https://developer.apple.com/account) under
**Membership details**.

### 3. Add the repository secrets

**Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12` | base64 of the `.p12` from step 1 |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `DEVELOPER_ID_APP` | the certificate's full common name, e.g. `Developer ID Application: Your Name (AB12CD34EF)` |
| `AC_APPLE_ID` | the Apple ID email that owns the membership |
| `AC_TEAM_ID` | the 10-character team ID, e.g. `AB12CD34EF` |
| `AC_PASSWORD` | the app-specific password from step 2 |

`DEVELOPER_ID_APP` must match the certificate name exactly. Confirm it with:

```bash
security find-identity -v -p codesigning
```

## Verifying the first signed release

Cut a release as usual (push a `vX.Y.Z` tag). The workflow's **Verify signature
and notarization** step now runs the real checks — `spctl --assess` for
Gatekeeper's verdict and `stapler validate` for the notarization ticket — and
fails the release if either does not pass.

Then confirm on a machine that has never run the app, ideally a fresh macOS user
account, that a **browser-downloaded** DMG (not `curl`, which sets no quarantine
flag) opens with no warning:

```bash
xattr -p com.apple.quarantine ~/Downloads/TokenMyBar-X.Y.Z.dmg  # should exist
spctl --assess --type open --context context:primary-signature -v ~/Downloads/TokenMyBar-X.Y.Z.dmg
```

## After it works

The quarantine workarounds exist only because releases are unsigned. Once a
notarized release ships and is verified on a clean machine, remove:

- the `xattr -rd com.apple.quarantine` call in `install.sh`
- the `postflight` block and `caveats` in the Homebrew cask
- the "ad-hoc signed, not notarized" notes in `README.md`,
  `docs/installation.md`, `docs/architecture.md`, and `docs/product-spec.md`

## Renewal

Developer ID certificates last five years; the membership renews yearly. If the
membership lapses, notarization starts failing and the release workflow fails at
the verify step rather than publishing a silently unnotarized DMG.
