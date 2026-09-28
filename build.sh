#!/bin/bash
set -euo pipefail
launcher_source="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" -gt 0 ]; then
    launcher_bundle="$1"
else
    launcher_stage="$(mktemp -d /private/tmp/ps12-build.XXXXXX)"
    launcher_bundle="$launcher_stage/PS1-2.app"
fi
launcher_resources="$launcher_bundle/Contents/Resources"
mkdir -p "$launcher_bundle/Contents/MacOS" "$launcher_resources" "$launcher_source/cache" "$launcher_source/AppIcon.iconset"
cp "$launcher_source/Info.plist" "$launcher_bundle/Contents/Info.plist"
cp "$launcher_source/Creditos.txt" "$launcher_resources/Creditos.txt"
cp "$launcher_source/assets/Logo.png" "$launcher_resources/Logo.png"
ditto --norsrc --noextattr "$launcher_source/assets/Covers" "$launcher_resources/Covers"
cp "$launcher_source/assets/PS1Startup.gif" "$launcher_source/assets/PS2Startup.gif" "$launcher_resources/"
for controller in PS1Controller PS2Controller; do
    sips -Z 1000 "$launcher_source/assets/$controller.png" --out "$launcher_resources/$controller.png" >/dev/null
done
xcrun swiftc -module-cache-path "$launcher_source/cache" "$launcher_source/MakeIcon.swift" -o "$launcher_source/MakeIcon"
"$launcher_source/MakeIcon" "$launcher_source/assets/Logo.png" "$launcher_source/AppIcon.iconset" "$launcher_resources/PS12ClassicIcon-v6.icns"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -framework AppKit -framework SwiftUI -framework GameController -framework ImageIO \
    -module-cache-path "$launcher_source/cache" "$launcher_source/PS12.swift" "$launcher_source/ControllerInput.swift" \
    "$launcher_source/EmulatorMonitor.swift" "$launcher_source/StartupAnimation.swift" "$launcher_source/HoverAnimation.swift" \
    "$launcher_source/GameCatalog.swift" "$launcher_source/GameCatalogView.swift" "$launcher_source/NowPlayingGameView.swift" \
    -o "$launcher_bundle/Contents/MacOS/PS12"
# Some synced folders add Finder metadata to newly created application bundles.
if xattr -p com.apple.FinderInfo "$launcher_bundle" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$launcher_bundle"
fi
codesign --force --sign - "$launcher_bundle"
codesign --verify --strict "$launcher_bundle"
plutil -lint "$launcher_bundle/Contents/Info.plist"
du -sh "$launcher_bundle"
