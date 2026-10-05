#!/bin/bash
set -euo pipefail
test_source="$(cd "$(dirname "$0")/.." && pwd)"
test_stage="$(mktemp -d /private/tmp/ps12-macho-tests.XXXXXX)"
trap 'case "$test_stage" in /private/tmp/ps12-macho-tests.??????) /bin/rm -rf -- "$test_stage" ;; esac' EXIT
/usr/bin/xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
    -module-cache-path "$test_stage/cache" \
    "$test_source/scripts/InspectMachO.swift" -o "$test_stage/InspectMachO"
/usr/bin/xcrun swiftc -parse-as-library -D MACHO_INSPECTOR_TESTS \
    -target arm64-apple-macosx14.0 -module-cache-path "$test_stage/cache" \
    "$test_source/scripts/InspectMachO.swift" "$test_source/tests/InspectMachOTests.swift" \
    -o "$test_stage/InspectMachOTests"
"$test_stage/InspectMachOTests" "$test_stage/InspectMachO"
