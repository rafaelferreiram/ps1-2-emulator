#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")/.." && pwd)"
test_stage="$(mktemp -d /private/tmp/ps12-responsive-layout-tests.XXXXXX)"
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
  -module-cache-path "$launcher_source/cache" \
  "$launcher_source/ResponsiveLayout.swift" \
  "$launcher_source/tests/ResponsiveLayoutTests.swift" -o "$test_stage/ResponsiveLayoutTests"
"$test_stage/ResponsiveLayoutTests"
