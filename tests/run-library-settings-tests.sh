#!/bin/bash
set -euo pipefail
library_source="$(cd "$(dirname "$0")/.." && pwd)"
library_test_dir="$(mktemp -d /private/tmp/ps12-library-settings.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework Foundation -framework Combine -module-cache-path "$library_test_dir/module-cache" \
  "$library_source/LibrarySettings.swift" "$library_source/tests/LibrarySettingsTests.swift" \
  -o "$library_test_dir/LibrarySettingsTests"
"$library_test_dir/LibrarySettingsTests"
