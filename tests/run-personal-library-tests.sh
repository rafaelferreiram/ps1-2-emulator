#!/bin/bash
set -euo pipefail
personal_source="$(cd "$(dirname "$0")/.." && pwd)"
personal_stage="$(mktemp -d /private/tmp/ps12-personal-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -framework Foundation -framework Combine \
  -module-cache-path "$personal_source/cache" "$personal_source/CatalogOrganization.swift" \
  "$personal_source/PersonalLibrary.swift" "$personal_source/tests/PersonalLibraryTests.swift" \
  -o "$personal_stage/PersonalLibraryTests"
"$personal_stage/PersonalLibraryTests"
