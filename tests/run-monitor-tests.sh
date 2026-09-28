#!/bin/bash
set -euo pipefail
monitor_test_dir="$(cd "$(dirname "$0")" && pwd)"
monitor_source_dir="$(dirname "$monitor_test_dir")"
monitor_test_build="$(mktemp -d /private/tmp/ps12-monitor-tests.XXXXXX)"
xcrun swiftc -D EMULATOR_MONITOR_TESTS -parse-as-library -target arm64-apple-macosx14.0 \
    -framework AppKit -framework Combine -module-cache-path "$monitor_source_dir/cache" \
    "$monitor_source_dir/EmulatorMonitor.swift" "$monitor_test_dir/EmulatorMonitorTests.swift" \
    -o "$monitor_test_build/EmulatorMonitorTests"
"$monitor_test_build/EmulatorMonitorTests"
