#!/bin/bash
# Synthetic fixtures only; never accesses the installed emulators or real SSD.
set -euo pipefail
if [ "$#" -gt 1 ]; then printf 'Usage: bash tests/run-portable-cover-tests.sh [source-root]\n' >&2; exit 2; fi
portable_test_sources="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
portable_source="${1:-$(cd -- "$portable_test_sources/.." && pwd -P)}"
portable_test_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-portable-cover-build.XXXXXX)"
portable_test_cleanup() {
    local status=$?
    if [ "$status" -eq 0 ]; then
        case "$portable_test_stage" in /private/tmp/ps12-portable-cover-build.??????)
            [ -d "$portable_test_stage" ] && [ ! -L "$portable_test_stage" ] && [ -O "$portable_test_stage" ] && /bin/rm -r -- "$portable_test_stage" ;;
        esac
    else
        printf 'Portable-cover test diagnostics: %s\n' "$portable_test_stage" >&2
    fi
    return "$status"
}
trap portable_test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/usr/bin/xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
    -framework Foundation -framework Combine -framework ImageIO -framework CoreGraphics \
    -module-cache-path "$portable_test_stage/module-cache" \
    "$portable_source/GameCatalog.swift" "$portable_source/CatalogCache.swift" "$portable_source/CoverImageCache.swift" \
    "$portable_test_sources/PortableCoverTests.swift" -o "$portable_test_stage/PortableCoverTests"
"$portable_test_stage/PortableCoverTests"
