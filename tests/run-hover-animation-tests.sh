#!/bin/bash
set -euo pipefail
hover_source="$(cd "$(dirname "$0")/.." && pwd)"
hover_test_dir="$(mktemp -d /private/tmp/ps12-hover-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework ImageIO \
  -module-cache-path "$hover_source/cache" \
  "$hover_source/HoverAnimation.swift" "$hover_source/tests/HoverAnimationTests.swift" \
  -o "$hover_test_dir/HoverAnimationTests"
"$hover_test_dir/HoverAnimationTests" "$hover_source/assets"
