#!/usr/bin/env bash
#
# Build TokenMyBar.app (and optionally a notarized DMG) from the SwiftPM
# executable. Signing and notarization are opt-in: set the credential env
# vars below and they run; leave them unset for an unsigned local build.
#
# Usage:
#   Scripts/package.sh [version]
#
# Version resolution: $1 → git tag (v1.2.3 → 1.2.3) → "0.0.0-dev".
#
# Signing (Developer ID) — set to enable codesigning + hardened runtime:
#   DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
#
# Notarization — set ALL three to notarize + staple the DMG:
#   AC_APPLE_ID="you@example.com"
#   AC_TEAM_ID="TEAMID"
#   AC_PASSWORD="app-specific-password"   # or use a stored notarytool profile
#
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PACKAGE_DIR/.build/release"
DIST_DIR="$PACKAGE_DIR/dist"
APP_NAME="TokenMyBar"
BUNDLE_ID="app.tokenmybar"
EXECUTABLE="TokenMyBar"
ENTITLEMENTS="$PACKAGE_DIR/Scripts/${APP_NAME}.entitlements"

# --- version --------------------------------------------------------------
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  if TAG="$(git -C "$PACKAGE_DIR" describe --tags --abbrev=0 2>/dev/null)"; then
    VERSION="${TAG#v}"
  else
    VERSION="0.0.0-dev"
  fi
fi
BUILD_NUMBER="$(git -C "$PACKAGE_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
echo "==> Packaging $APP_NAME $VERSION (build $BUILD_NUMBER)"

# --- build ----------------------------------------------------------------
echo "==> swift build -c release"
swift build -c release --package-path "$PACKAGE_DIR" --product "$EXECUTABLE"

# --- assemble bundle ------------------------------------------------------
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 coodyapp. MIT Licensed.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

# --- sign -----------------------------------------------------------------
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "==> Codesigning with hardened runtime"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVELOPER_ID_APP" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
  echo "==> DEVELOPER_ID_APP not set — skipping codesign (unsigned build)"
fi

# --- dmg ------------------------------------------------------------------
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
echo "==> Building DMG"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH" >/dev/null

# --- notarize -------------------------------------------------------------
if [[ -n "${DEVELOPER_ID_APP:-}" && -n "${AC_APPLE_ID:-}" && -n "${AC_TEAM_ID:-}" && -n "${AC_PASSWORD:-}" ]]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_PASSWORD" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  echo "==> Notarized and stapled"
else
  echo "==> Notarization credentials not set — skipping (DMG is not notarized)"
fi

echo "==> Done: $APP_BUNDLE"
echo "==> Done: $DMG_PATH"
