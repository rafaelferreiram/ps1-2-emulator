#!/bin/bash
set -euo pipefail
session_source="$(cd "$(dirname "$0")/.." && pwd)"
session_stage="$(mktemp -d /private/tmp/ps12-session-tests.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -framework Foundation -framework Combine \
  -module-cache-path "$session_source/cache" "$session_source/CatalogOrganization.swift" \
  "$session_source/SessionLifecycle.swift" "$session_source/tests/SessionLifecycleTests.swift" \
  -o "$session_stage/SessionLifecycleTests"
"$session_stage/SessionLifecycleTests"
