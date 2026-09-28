#!/bin/bash
set -euo pipefail
catalog_source="$(cd "$(dirname "$0")/.." && pwd)"
catalog_test_dir="$(mktemp -d /private/tmp/ps12-catalog-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework Foundation -framework Combine -framework ImageIO \
  -module-cache-path "$catalog_source/cache" \
  "$catalog_source/GameCatalog.swift" "$catalog_source/tests/GameCatalogTests.swift" \
  -o "$catalog_test_dir/GameCatalogTests"
"$catalog_test_dir/GameCatalogTests" "$@"
