#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")/.." && pwd)"
experience_test_stage="$(mktemp -d /private/tmp/ps12-experience-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -module-cache-path "$launcher_source/cache" \
  "$launcher_source/ConsoleExperience.swift" "$launcher_source/tests/ConsoleExperienceTests.swift" \
  -o "$experience_test_stage/ConsoleExperienceTests"
"$experience_test_stage/ConsoleExperienceTests"
