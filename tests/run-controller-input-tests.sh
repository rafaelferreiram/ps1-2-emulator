#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")/.." && pwd)"
controller_test_stage="$(mktemp -d /private/tmp/ps12-controller-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework AppKit -framework GameController -module-cache-path "$launcher_source/cache" \
  "$launcher_source/ControllerInput.swift" "$launcher_source/tests/ControllerInputTests.swift" \
  -o "$controller_test_stage/ControllerInputTests"
"$controller_test_stage/ControllerInputTests"
