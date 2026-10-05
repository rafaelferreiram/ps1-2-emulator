#!/bin/bash
# Developer-side packaging only. The resulting installer does not compile code.
set -euo pipefail
dmg_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ "$#" -gt 1 ]; then printf 'Usage: bash scripts/build-dmg.sh [output-directory]\n' >&2; exit 2; fi
source "$dmg_source/scripts/source-check.sh"
ps12_source_check "$dmg_source"
source "$dmg_source/scripts/installer-lib.sh"
[ "$(/usr/bin/uname -s)" = Darwin ] && [ "$(/usr/bin/uname -m)" = arm64 ] || {
    printf 'Build this release on an Apple Silicon Mac.\n' >&2; exit 1;
}
installer_check_tools
dmg_version="$(installer_plist "$dmg_source/Info.plist" CFBundleShortVersionString)"
dmg_build="$(installer_plist "$dmg_source/Info.plist" CFBundleVersion)"
[[ "$dmg_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$dmg_build" =~ ^[0-9]+$ ]] || exit 1
dmg_output="${1:-$dmg_source/dist}"
/bin/mkdir -p "$dmg_output"
dmg_output="$(cd -- "$dmg_output" && pwd -P)"
dmg_name="PS1-2-Installer-$dmg_version-arm64.dmg"
for dmg_target in "$dmg_output/$dmg_name" "$dmg_output/$dmg_name.sha256"; do
    if [ -e "$dmg_target" ] || [ -L "$dmg_target" ]; then
        printf 'Output already exists; choose a new output directory: %s\n' "$dmg_target" >&2; exit 1
    fi
done
dmg_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-dmg-build.XXXXXX)"
case "$dmg_stage" in /private/tmp/ps12-dmg-build.??????)
    [ -d "$dmg_stage" ] && [ ! -L "$dmg_stage" ] && [ -O "$dmg_stage" ] || exit 1 ;;
    *) exit 1 ;;
esac
readonly dmg_stage
dmg_publish_stage=''
dmg_cleanup() {
    local status=$?
    if [ "$status" -eq 0 ]; then
        /bin/rm -r -- "$dmg_stage"
        if [ -n "$dmg_publish_stage" ]; then /bin/rmdir "$dmg_publish_stage" || true; fi
    else
        printf 'Packaging failed (%s). Diagnostics preserved: %s\n' "$status" "$dmg_stage" >&2
        if [ -n "$dmg_publish_stage" ]; then printf 'Unpublished output: %s\n' "$dmg_publish_stage" >&2; fi
    fi
    return "$status"
}
trap dmg_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
dmg_app="$dmg_stage/image/Install PS1-2.app"
dmg_resources="$dmg_app/Contents/Resources"
dmg_installer="$dmg_resources/Installer"
/bin/mkdir -p "$dmg_app/Contents/MacOS" "$dmg_installer/scripts" "$dmg_installer/payload" "$dmg_stage/module-cache"
/bin/cp "$dmg_source/scripts/SetupInfo.plist" "$dmg_app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$dmg_version" "$dmg_app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$dmg_build" "$dmg_app/Contents/Info.plist"
/bin/cp "$dmg_source/docs/images/icon.png" "$dmg_resources/icon.png"
/bin/cp "$dmg_source/install.sh" "$dmg_installer/install.sh"
/bin/cp "$dmg_source/scripts/installer-lib.sh" "$dmg_source/scripts/payload-check.sh" "$dmg_installer/scripts/"
/usr/bin/plutil -create xml1 "$dmg_installer/distribution.plist"
/usr/bin/plutil -insert PS12Distribution -string prebuilt-v1 "$dmg_installer/distribution.plist"
/usr/bin/plutil -insert Version -string "$dmg_version" "$dmg_installer/distribution.plist"
/usr/bin/plutil -insert Build -string "$dmg_build" "$dmg_installer/distribution.plist"

printf 'Building the launcher and standalone installer helpers…\n'
/bin/bash "$dmg_source/build.sh" "$dmg_installer/payload/PS1-2.app"
/bin/cp "$dmg_installer/payload/PS1-2.app/Contents/Resources/PS12ClassicIcon-v7.icns" "$dmg_resources/setup.icns"
for dmg_helper in MoveApp InspectMachO; do
    dmg_swift_arguments=()
    if [ "$dmg_helper" = InspectMachO ]; then dmg_swift_arguments=(-parse-as-library); fi
    /usr/bin/xcrun swiftc -O -target arm64-apple-macosx14.0 \
        -module-cache-path "$dmg_stage/module-cache" \
        ${dmg_swift_arguments[@]+"${dmg_swift_arguments[@]}"} \
        "$dmg_source/scripts/$dmg_helper.swift" -o "$dmg_installer/payload/$dmg_helper"
    /usr/bin/codesign --force --sign - "$dmg_installer/payload/$dmg_helper"
    /usr/bin/codesign --verify --strict "$dmg_installer/payload/$dmg_helper"
done
/usr/bin/xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
    -framework AppKit -framework SwiftUI -module-cache-path "$dmg_stage/module-cache" \
    "$dmg_source/scripts/SetupWizard.swift" -o "$dmg_app/Contents/MacOS/SetupWizard"
/bin/cp "$dmg_source/docs/DMG-README.txt" "$dmg_stage/image/Read Me.txt"
/bin/cp "$dmg_source/docs/DMG-README.txt" "$dmg_resources/Read Me.txt"
/bin/cp "$dmg_source/Creditos.txt" "$dmg_resources/Creditos.txt"
/usr/bin/codesign --force --sign - "$dmg_app"
/usr/bin/codesign --verify --deep --strict "$dmg_app"
source "$dmg_installer/scripts/payload-check.sh"
ps12_payload_check "$dmg_installer"

printf 'Creating a compressed read-only disk image…\n'
# Build the HFS+ filesystem as a file, without creating or mounting a temporary
# disk device. This also works in build environments without Disk Arbitration.
/usr/bin/hdiutil makehybrid -hfs -hfs-volume-name 'PS1-2 Installer' \
    -o "$dmg_stage/filesystem.dmg" "$dmg_stage/image"
/usr/bin/hdiutil convert -format UDZO -tgtimagekey zlib-level=9 \
    -o "$dmg_stage/$dmg_name" "$dmg_stage/filesystem.dmg"
/usr/bin/hdiutil verify "$dmg_stage/$dmg_name"
# Publish exclusively on the output filesystem; never overwrite an old release.
dmg_publish_stage="$(/usr/bin/mktemp -d "$dmg_output/.ps12-dmg-output.XXXXXX")"
/bin/cp "$dmg_stage/$dmg_name" "$dmg_publish_stage/$dmg_name"
(cd "$dmg_publish_stage" && /usr/bin/shasum -a 256 "$dmg_name" > "$dmg_name.sha256")
"$dmg_installer/payload/MoveApp" "$dmg_publish_stage/$dmg_name" "$dmg_output/$dmg_name"
"$dmg_installer/payload/MoveApp" "$dmg_publish_stage/$dmg_name.sha256" "$dmg_output/$dmg_name.sha256"
printf '\nDMG: %s\nSHA-256: %s\n' "$dmg_output/$dmg_name" "$dmg_output/$dmg_name.sha256"
printf 'Local ad hoc signatures only: this artifact is not Developer ID signed or Apple-notarized.\n'
