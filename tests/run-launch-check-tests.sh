#!/bin/bash
set -euo pipefail
launch_source="$(cd "$(dirname "$0")/.." && pwd)"
launch_test_dir="$(mktemp -d /private/tmp/ps12-launch-checks.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework Foundation -module-cache-path "$launch_source/cache" \
  "$launch_source/GameLaunchCheck.swift" "$launch_source/tests/GameLaunchCheckTests.swift" \
  -o "$launch_test_dir/GameLaunchCheckTests"
"$launch_test_dir/GameLaunchCheckTests"
