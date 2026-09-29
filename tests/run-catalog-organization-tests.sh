#!/bin/bash
set -euo pipefail
catalog_source="$(cd "$(dirname "$0")/.." && pwd)"
catalog_test_dir="$(mktemp -d /private/tmp/ps12-catalog-organization.XXXXXX)"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework Foundation -framework Combine -module-cache-path "$catalog_test_dir/module-cache" \
  "$catalog_source/CatalogOrganization.swift" "$catalog_source/tests/CatalogOrganizationTests.swift" \
  -o "$catalog_test_dir/CatalogOrganizationTests"
"$catalog_test_dir/CatalogOrganizationTests"
