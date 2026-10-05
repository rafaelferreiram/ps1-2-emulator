#!/bin/bash
set -euo pipefail
test_source="$(cd "$(dirname "$0")/.." && pwd)"
test_stage="$(mktemp -d /private/tmp/ps12-wizard-tests.XXXXXX)"
trap 'case "$test_stage" in /private/tmp/ps12-wizard-tests.??????) /bin/rm -rf -- "$test_stage" ;; esac' EXIT
/usr/bin/xcrun swiftc -parse-as-library -D SETUP_WIZARD_TESTS \
    -target arm64-apple-macosx14.0 -framework AppKit -framework SwiftUI \
    -module-cache-path "$test_source/cache" \
    "$test_source/scripts/SetupWizard.swift" "$test_source/tests/SetupWizardTests.swift" \
    -o "$test_stage/SetupWizardTests"
"$test_stage/SetupWizardTests"
