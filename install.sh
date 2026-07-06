#!/usr/bin/env bash
#
# TokenMyBar installer — downloads the release DMG, verifies its checksum,
# and installs TokenMyBar.app into /Applications.
#
# Why this exists: releases are ad-hoc signed (no Apple Developer ID yet).
# Gatekeeper only assesses quarantined files, and curl downloads never get
# the com.apple.quarantine flag, so an install through this script launches
# without the "Apple could not verify..." block.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/coodyapp/token-my-bar/main/install.sh | bash
#   ./install.sh [version]        # e.g. ./install.sh 1.0.7 (default: latest)
set -euo pipefail

REPO="coodyapp/token-my-bar"
APP_NAME="TokenMyBar"
INSTALL_DIR="/Applications"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "$APP_NAME only runs on macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "$APP_NAME requires Apple Silicon."

version="${1:-}"
if [[ -z "$version" ]]; then
  log "Resolving latest release..."
  tag=$(curl -fsSL --connect-timeout 10 "https://api.github.com/repos/$REPO/releases/latest" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [[ -n "$tag" ]] || fail "Could not determine the latest release tag."
  version="${tag#v}"
fi

dmg="$APP_NAME-$version.dmg"
base_url="https://github.com/$REPO/releases/download/v$version"

tmp_dir=$(mktemp -d)
mount_point=""
cleanup() {
  if [[ -n "$mount_point" ]]; then
    hdiutil detach "$mount_point" -quiet 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

log "Downloading $dmg..."
curl -fSL --connect-timeout 10 -o "$tmp_dir/$dmg" "$base_url/$dmg" ||
  fail "Download failed. Does release v$version exist?"
curl -fsSL --connect-timeout 10 -o "$tmp_dir/$dmg.sha256" "$base_url/$dmg.sha256" ||
  fail "Checksum file download failed."

log "Verifying checksum..."
# The .sha256 asset embeds the CI build path, so compare hash fields instead
# of `shasum -c`.
expected=$(awk '{print $1}' "$tmp_dir/$dmg.sha256")
actual=$(shasum -a 256 "$tmp_dir/$dmg" | awk '{print $1}')
[[ -n "$expected" && "$expected" == "$actual" ]] ||
  fail "Checksum mismatch: expected $expected, got $actual."

log "Mounting DMG..."
mount_point=$(hdiutil attach "$tmp_dir/$dmg" -nobrowse -readonly |
  awk -F'\t' '$NF ~ /^\/Volumes\// { print $NF; exit }')
[[ -n "$mount_point" && -d "$mount_point/$APP_NAME.app" ]] ||
  fail "$APP_NAME.app not found in DMG."

if pgrep -xq "$APP_NAME"; then
  log "Quitting running $APP_NAME..."
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 ||
    pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 1
fi

log "Installing $INSTALL_DIR/$APP_NAME.app..."
if [[ -w "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR/${APP_NAME:?}.app"
  cp -R "$mount_point/$APP_NAME.app" "$INSTALL_DIR/"
else
  log "Admin access required for $INSTALL_DIR"
  sudo rm -rf "$INSTALL_DIR/${APP_NAME:?}.app"
  sudo cp -R "$mount_point/$APP_NAME.app" "$INSTALL_DIR/"
fi

# curl downloads carry no quarantine flag, but clear any stale one left by a
# previous browser-downloaded install.
xattr -rd com.apple.quarantine "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

hdiutil detach "$mount_point" -quiet
mount_point=""

log "Installed $APP_NAME $version. Launching..."
open "$INSTALL_DIR/$APP_NAME.app"
