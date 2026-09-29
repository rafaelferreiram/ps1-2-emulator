#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")/.." && pwd)"
launcher_preview_stage="$(mktemp -d /private/tmp/ps12-preview-tests.XXXXXX)"
xcrun swiftc -D LAUNCHER_MODEL_TESTS -O -parse-as-library -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework GameController -framework ImageIO \
  -module-cache-path "$launcher_source/cache" \
  "$launcher_source/PS12.swift" "$launcher_source/ControllerInput.swift" \
  "$launcher_source/EmulatorMonitor.swift" "$launcher_source/StartupAnimation.swift" \
  "$launcher_source/HoverAnimation.swift" "$launcher_source/GameCatalog.swift" \
  "$launcher_source/CatalogOrganization.swift" \
  "$launcher_source/GameCatalogView.swift" "$launcher_source/NowPlayingGameView.swift" \
  "$launcher_source/CatalogCache.swift" "$launcher_source/CoverImageCache.swift" \
  "$launcher_source/GameLaunchCheck.swift" \
  "$launcher_source/StorageNoticeView.swift" \
  "$launcher_source/LibrarySettings.swift" "$launcher_source/LibrarySettingsView.swift" "$launcher_source/ResponsiveLayout.swift" \
  "$launcher_source/tests/LauncherPreviewTests.swift" \
  -o "$launcher_preview_stage/LauncherPreviewTests"
"$launcher_preview_stage/LauncherPreviewTests"
