#!/bin/bash
# Packs dist/OpenHoop.app into dist/OpenHoop-<version>.dmg for people to download: open it, then drag OpenHoop onto
# Applications. It works on a copy, so the app in dist (which may be open) is never changed.
#
# Signing and notarizing are optional, set by two environment variables (nothing personal is kept in this file):
#   SIGN_IDENTITY   a "Developer ID Application" certificate in your keychain (its name or its SHA-1 hash, as
#                   `security find-identity -v -p codesigning` lists them). Without it the DMG holds the locally
#                   signed app, which other Macs warn about.
#   NOTARY_PROFILE  Apple ID credentials saved once with `xcrun notarytool store-credentials`. With it (and
#                   SIGN_IDENTITY), Apple checks the DMG and its approval is attached ("stapled") to it, so the app
#                   opens on other Macs without a warning.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=dist/OpenHoop.app
[ -d "$APP" ] || { echo "No app to pack: run ./scripts/build.sh first." >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/OpenHoop-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT   # the copy is thrown away however the script ends
mkdir "$STAGE/OpenHoop"
# ditto copies the app exactly (links, permissions and all), which a plain cp doesn't always do.
ditto "$APP" "$STAGE/OpenHoop/OpenHoop.app"
COPY="$STAGE/OpenHoop/OpenHoop.app"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Sign from the inside out: every program and library in the format helper, then the app around them.
  # --options runtime turns on Apple's "hardened runtime" and --timestamp adds Apple's time stamp; notarizing
  # needs both on every piece of code.
  find "$COPY/Contents/Resources/format-helper" -type f -print0 | while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q '^Mach-O'; then   # Mach-O: a compiled Mac program or library
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$file"
    fi
  done
  # Sparkle's helpers, then Sparkle itself, in the order its guide gives (no --deep: each piece is signed on its own).
  SPARKLE="$COPY/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$COPY"
  codesign --verify --deep --strict "$COPY"
  echo "Signed the app."
fi

ln -s /Applications "$STAGE/OpenHoop/Applications"   # so the DMG's window shows where to drag the app
rm -f "$DMG"
hdiutil create -volname "OpenHoop" -srcfolder "$STAGE/OpenHoop" -format UDZO -quiet "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Sending the DMG to Apple to notarize (usually a few minutes)…"
    # tee shows Apple's progress as it comes while also keeping it, to check the result below.
    result=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee /dev/stderr)
    if ! grep -q "status: Accepted" <<<"$result"; then
      id=$(grep -m1 -E '^ *id:' <<<"$result" | awk '{print $2}')
      echo "Apple didn't accept it. To see why: xcrun notarytool log $id --keychain-profile \"$NOTARY_PROFILE\"" >&2
      exit 1
    fi
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  fi
fi
printf 'Made %s\n' "$DMG"
