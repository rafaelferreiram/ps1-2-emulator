#!/bin/bash
set -euo pipefail
test_source="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
test_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-hfs-tests.XXXXXX)"
cleanup() {
    local status=$?
    case "$test_stage" in /private/tmp/ps12-hfs-tests.??????)
        if [ -d "$test_stage" ] && [ ! -L "$test_stage" ] && [ -O "$test_stage" ]; then /bin/rm -r -- "$test_stage"; fi ;;
    esac
    return "$status"
}
trap cleanup EXIT
/usr/bin/xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
    -module-cache-path "$test_stage/cache" "$test_source/scripts/NormalizeHFS.swift" -o "$test_stage/NormalizeHFS"
/usr/bin/xcrun swiftc -parse-as-library -D HFS_METADATA_TESTS -target arm64-apple-macosx14.0 \
    -module-cache-path "$test_stage/cache" "$test_source/scripts/NormalizeHFS.swift" \
    "$test_source/tests/NormalizeHFSTests.swift" -o "$test_stage/NormalizeHFSTests"
"$test_stage/NormalizeHFSTests" "$test_stage/NormalizeHFS"
