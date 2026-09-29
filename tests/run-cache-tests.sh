#!/bin/bash
set -euo pipefail
catalog_source="$(cd "$(dirname "$0")/.." && pwd)"
catalog_test_dir="$(mktemp -d /private/tmp/ps12-cache-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework Foundation -framework Combine -framework ImageIO \
  -module-cache-path "$catalog_source/cache" \
  "$catalog_source/GameCatalog.swift" "$catalog_source/CatalogCache.swift" \
  "$catalog_source/CoverImageCache.swift" \
  "$catalog_source/tests/CatalogCacheTests.swift" \
  -o "$catalog_test_dir/CatalogCacheTests"
"$catalog_test_dir/CatalogCacheTests"
