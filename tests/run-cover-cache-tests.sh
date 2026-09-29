#!/bin/bash
set -euo pipefail
cover_source="$(cd "$(dirname "$0")/.." && pwd)"
cover_test_build="$(mktemp -d /private/tmp/ps12-cover-cache-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework CoreGraphics -framework ImageIO -framework CryptoKit \
  -module-cache-path "$cover_source/cache" \
  "$cover_source/CoverImageCache.swift" "$cover_source/tests/CoverImageCacheTests.swift" \
  -o "$cover_test_build/CoverImageCacheTests"
"$cover_test_build/CoverImageCacheTests"
