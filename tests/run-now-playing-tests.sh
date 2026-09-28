#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")/.." && pwd)"
test_stage="$(mktemp -d /private/tmp/ps12-now-playing-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework ImageIO \
  -module-cache-path "$launcher_source/cache" \
  "$launcher_source/GameCatalog.swift" "$launcher_source/NowPlayingGameView.swift" \
  "$launcher_source/tests/NowPlayingLayoutTests.swift" -o "$test_stage/NowPlayingLayoutTests"
"$test_stage/NowPlayingLayoutTests"
