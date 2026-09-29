#!/bin/bash
set -euo pipefail
installer_test_source="$(cd "$(dirname "$0")/.." && pwd)"
/bin/bash "$installer_test_source/tests/InstallerTests.sh"
