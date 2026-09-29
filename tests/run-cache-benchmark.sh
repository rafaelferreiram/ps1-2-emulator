#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_stage="$(mktemp -d /private/tmp/ps12-cache-benchmark.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework Foundation -framework Combine -framework ImageIO \
  -module-cache-path "$launcher_source/cache" \
  "$launcher_source/GameCatalog.swift" "$launcher_source/CatalogCache.swift" \
  "$launcher_source/CoverImageCache.swift" "$launcher_source/tests/CacheBenchmark.swift" \
  -o "$benchmark_stage/CacheBenchmark"
"$benchmark_stage/CacheBenchmark" "$launcher_source/assets/Covers"
