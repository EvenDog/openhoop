#!/bin/bash
# Build a self-contained, locally signed Mac app with its own embroidery-format helper.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
# The app is "universal": one copy for Apple Silicon (arm64) and one for Intel (x86_64) in the same file, and each Mac
# runs its own. Built for two chips, SwiftPM puts its output in another folder, so it's asked where (--show-bin-path).
SWIFT_BUILD=(swift build --disable-sandbox --cache-path .build/package-cache -c release --arch arm64 --arch x86_64)
"${SWIFT_BUILD[@]}"   # release (optimized): large fills generate ~40x faster than debug
BIN=$("${SWIFT_BUILD[@]}" --show-bin-path)
# The format helper is packed from .venv's Python, so that Python must be universal too. Homebrew's is Apple Silicon
# only; the one from python.org's installer has both chips (see docs/DEVELOPMENT.md).
PYTHON_ORG=/Library/Frameworks/Python.framework/Versions/Current/bin/python3
if [ ! -x .venv/bin/python ]; then
  [ -x "$PYTHON_ORG" ] || { echo "Install Python 3 from python.org first (see docs/DEVELOPMENT.md)." >&2; exit 1; }
  "$PYTHON_ORG" -m venv .venv
  .venv/bin/python -m pip install -r requirements-build.txt
fi
if ! lipo -archs .venv/bin/python | grep -q x86_64; then
  echo ".venv's Python runs on Apple Silicon only. Install Python 3 from python.org, delete .venv, and build again." >&2
  exit 1
fi
export PYINSTALLER_CONFIG_DIR="$PWD/.build/pyinstaller-cache"
.venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name format-helper \
  --distpath .build/helper-dist --workpath .build/helper-work --specpath .build \
  --target-architecture universal2 Helper/format_helper.py
APP="$PWD/dist/OpenHoop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/EmbroideryApp" "$APP/Contents/MacOS/EmbroideryApp"
# Sparkle, the updater (Updates.swift), goes in Contents/Frameworks, where the app is told to look for it (an
# "rpath"). SwiftPM's own rpath points into this Mac's build folder, so it comes out: it would show the folder's path
# to anyone who looked, and it's no use on another Mac. Sparkle's XPC services are only for sandboxed apps, which
# OpenHoop isn't, so they're left out (Sparkle's guide says they may be removed).
rm -rf "$APP/Contents/Frameworks"; mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
otool -l "$APP/Contents/MacOS/EmbroideryApp" | awk '/LC_RPATH/ { getline; getline; if ($2 ~ /PackageFrameworks/) print $2 }' | while read -r path; do
  install_name_tool -delete_rpath "$path" "$APP/Contents/MacOS/EmbroideryApp"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/EmbroideryApp"
if [ -d "$APP/Contents/Resources/format-helper" ]; then
  rm -rf "$APP/Contents/Resources/format-helper"
fi
cp -R .build/helper-dist/format-helper "$APP/Contents/Resources/format-helper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# OpenHoop's own license (GPL-3.0) travels with the app, as the license asks.
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp Resources/Python-LICENSE.txt "$APP/Contents/Resources/Python-LICENSE.txt"
cp Resources/Clipper2-LICENSE.txt "$APP/Contents/Resources/Clipper2-LICENSE.txt"
cp Resources/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
# The app icon, drawn by scripts/make-icon.swift.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Hand-digitized embroidery fonts (each folder keeps its own LICENSE); see scripts/fetch-embroidery-fonts.sh.
rm -rf "$APP/Contents/Resources/EmbroideryFonts"
cp -R Resources/EmbroideryFonts "$APP/Contents/Resources/EmbroideryFonts"
# Thread charts made from pyembroidery's machine palettes; see scripts/make-thread-charts.py.
rm -rf "$APP/Contents/Resources/ThreadCharts"
cp -R Resources/ThreadCharts "$APP/Contents/Resources/ThreadCharts"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
