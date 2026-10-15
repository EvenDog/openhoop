#!/bin/bash
# Build a self-contained, locally signed Mac app with its own embroidery-format helper.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --cache-path .build/package-cache -c release   # optimized: large fills generate ~40x faster than debug
if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
  .venv/bin/python -m pip install -r requirements-build.txt
fi
export PYINSTALLER_CONFIG_DIR="$PWD/.build/pyinstaller-cache"
.venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name format-helper \
  --distpath .build/helper-dist --workpath .build/helper-work --specpath .build \
  --target-architecture arm64 Helper/format_helper.py
APP="$PWD/dist/OpenHoop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/EmbroideryApp "$APP/Contents/MacOS/EmbroideryApp"
if [ -d "$APP/Contents/Resources/format-helper" ]; then
  rm -rf "$APP/Contents/Resources/format-helper"
fi
cp -R .build/helper-dist/format-helper "$APP/Contents/Resources/format-helper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp Resources/Python-LICENSE.txt "$APP/Contents/Resources/Python-LICENSE.txt"
cp Resources/Clipper2-LICENSE.txt "$APP/Contents/Resources/Clipper2-LICENSE.txt"
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
