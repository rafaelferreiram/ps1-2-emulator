#!/bin/bash
set -euo pipefail
launcher_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -r "$launcher_source/scripts/source-check.sh" ] || {
    printf 'O download do projeto está incompleto: scripts/source-check.sh não foi encontrado. Extraia toda a pasta novamente.\n' >&2
    exit 1
}
source "$launcher_source/scripts/source-check.sh"
ps12_source_check "$launcher_source"

# A downloaded folder may be read-only or moved. Keep all compiler and icon
# intermediates in our own temporary directory; only the final app is an output.
launcher_work="$(/usr/bin/mktemp -d /private/tmp/ps12-build-work.XXXXXX)"
case "$launcher_work" in
    /private/tmp/ps12-build-work.??????)
        [ -d "$launcher_work" ] && [ ! -L "$launcher_work" ] && [ -O "$launcher_work" ] || exit 1 ;;
    *) printf 'Pasta temporária inesperada; preservada: %s\n' "$launcher_work" >&2; exit 1 ;;
esac
readonly launcher_work
launcher_cleanup() {
    local status=$?
    if [ "$status" -eq 0 ]; then
        case "$launcher_work" in /private/tmp/ps12-build-work.??????)
            if [ -d "$launcher_work" ] && [ ! -L "$launcher_work" ] && [ -O "$launcher_work" ]; then
                /bin/rm -r -- "$launcher_work" || printf 'Arquivos temporários preservados: %s\n' "$launcher_work" >&2
            fi ;;
        esac
    else
        printf 'A compilação falhou (código %s). Arquivos temporários para diagnóstico: %s\n' "$status" "$launcher_work" >&2
    fi
    return "$status"
}
trap launcher_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$#" -gt 0 ]; then
    launcher_bundle="$1"
else
    launcher_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-build.XXXXXX)"
    launcher_bundle="$launcher_stage/PS1-2.app"
fi
launcher_resources="$launcher_bundle/Contents/Resources"
mkdir -p "$launcher_bundle/Contents/MacOS" "$launcher_resources" "$launcher_work/module-cache" "$launcher_work/AppIcon.iconset"
cp "$launcher_source/Info.plist" "$launcher_bundle/Contents/Info.plist"
cp "$launcher_source/Creditos.txt" "$launcher_resources/Creditos.txt"
cp "$launcher_source/assets/Logo.png" "$launcher_resources/Logo.png"
ditto --norsrc --noextattr "$launcher_source/assets/Covers" "$launcher_resources/Covers"
# ditto preserves directory modes from a read-only source. Only normalize our
# copied artwork so the owned temporary bundle can be cleaned up after install.
chmod -R u+w "$launcher_resources/Covers"
cp "$launcher_source/assets/PS1Startup.gif" "$launcher_source/assets/PS2Startup.gif" "$launcher_resources/"
for controller in PS1Controller PS2Controller; do
    sips -Z 1000 "$launcher_source/assets/$controller.png" --out "$launcher_resources/$controller.png" >/dev/null
done
xcrun swiftc -module-cache-path "$launcher_work/module-cache" -framework AppKit -framework QuartzCore -framework ImageIO \
    "$launcher_source/MakeIcon.swift" -o "$launcher_work/MakeIcon"
"$launcher_work/MakeIcon" "$launcher_source/assets/Logo.png" "$launcher_work/AppIcon.iconset" "$launcher_resources/PS12ClassicIcon-v7.icns"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -framework AppKit -framework SwiftUI -framework GameController -framework ImageIO \
    -module-cache-path "$launcher_work/module-cache" "$launcher_source/PS12.swift" "$launcher_source/ControllerInput.swift" \
    "$launcher_source/EmulatorMonitor.swift" "$launcher_source/StartupAnimation.swift" "$launcher_source/HoverAnimation.swift" \
    "$launcher_source/GameCatalog.swift" "$launcher_source/CatalogOrganization.swift" "$launcher_source/GameCatalogView.swift" "$launcher_source/NowPlayingGameView.swift" \
    "$launcher_source/CatalogCache.swift" "$launcher_source/CoverImageCache.swift" \
    "$launcher_source/GameLaunchCheck.swift" \
    "$launcher_source/PersonalLibrary.swift" "$launcher_source/ConsoleExperience.swift" \
    "$launcher_source/SessionLifecycle.swift" "$launcher_source/LauncherDialogs.swift" \
    "$launcher_source/StorageNoticeView.swift" \
    "$launcher_source/LibrarySettings.swift" "$launcher_source/LibrarySettingsView.swift" "$launcher_source/ResponsiveLayout.swift" \
    -o "$launcher_bundle/Contents/MacOS/PS12"
# Some synced folders add Finder metadata to newly created application bundles.
if xattr -p com.apple.FinderInfo "$launcher_bundle" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$launcher_bundle"
fi
codesign --force --sign - "$launcher_bundle"
codesign --verify --strict "$launcher_bundle"
plutil -lint "$launcher_bundle/Contents/Info.plist"
du -sh "$launcher_bundle"
