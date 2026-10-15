#!/bin/bash
# Exercise geometry, persistence, shortcut conflicts and real PES encoding.
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift test --disable-sandbox --cache-path .build/package-cache
.venv/bin/python -m unittest discover -s Helper -p 'test_*.py' -v
