#!/bin/bash
set -euo pipefail
bootstrap_test_source="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
/bin/bash -n "$bootstrap_test_source/Instalar.command"
/usr/bin/plutil -lint "$bootstrap_test_source/scripts/SetupInfo.plist"
/bin/bash "$bootstrap_test_source/tests/BootstrapTests.sh"
