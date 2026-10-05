#!/bin/bash
# Real image integration: installs only the bundled launcher into an owned temp
# directory. No emulator downloads, launch, real-app replacement or LS writes.
set -euo pipefail
if { [ "$#" -ne 1 ] && [ "$#" -ne 3 ]; } || [ ! -f "$1" ]; then
    printf 'Usage: bash tests/run-dmg-tests.sh /path/to/installer.dmg [--mounted /Volumes/installer]\n' >&2; exit 2
fi
if [ "$#" -eq 3 ] && { [ "$2" != --mounted ] || [[ "$3" != /Volumes/* ]] || [ ! -d "$3" ] || [ -L "$3" ]; }; then
    printf 'Use --mounted with an existing read-only image mounted in Finder.\n' >&2; exit 2
fi
dmg_test_image="$(cd -- "$(dirname -- "$1")" && pwd -P)/$(basename -- "$1")"
dmg_test_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-dmg-tests.XXXXXX)"
dmg_test_mount="$dmg_test_stage/Mounted Installer"
dmg_test_mounted=no
dmg_test_checks=0
dmg_test_cleanup() {
    local status=$?
    if [ "$dmg_test_mounted" = yes ]; then
        if ! /usr/bin/hdiutil detach "$dmg_test_mount" >/dev/null; then
            printf 'Unmount this test image manually; temporary files preserved: %s\n' "$dmg_test_stage" >&2
            return 1
        fi
    fi
    if [ "$status" -eq 0 ]; then
        case "$dmg_test_stage" in /private/tmp/ps12-dmg-tests.??????)
            [ ! -L "$dmg_test_stage" ] && [ -O "$dmg_test_stage" ] && /bin/rm -r -- "$dmg_test_stage" ;;
        esac
    else
        printf 'Failure diagnostics preserved: %s\n' "$dmg_test_stage" >&2
    fi
    return "$status"
}
trap dmg_test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
dmg_test_require() {
    local message="$1"; shift
    if ! "$@"; then printf 'FAIL: %s\n' "$message" >&2; exit 1; fi
    dmg_test_checks=$((dmg_test_checks + 1))
}
/bin/mkdir -p "$dmg_test_mount" "$dmg_test_stage/Personal Applications"
dmg_test_require 'compressed DMG checksum' /usr/bin/hdiutil verify "$dmg_test_image"
if [ "$#" -eq 3 ]; then
    # Finder can mount images on hosts whose terminal cannot reach Disk
    # Arbitration. Never detach an externally managed mount during cleanup.
    dmg_test_mount="$(cd -- "$3" && pwd -P)"
    /usr/bin/hdiutil info -plist > "$dmg_test_stage/images.plist"
    dmg_test_image_index=0
    dmg_test_found=no
    while dmg_test_reported_image="$(/usr/bin/plutil -extract "images.$dmg_test_image_index.image-path" raw -o - "$dmg_test_stage/images.plist" 2>/dev/null)"; do
        if [ "$dmg_test_reported_image" = "$dmg_test_image" ]; then
            dmg_test_require 'Finder image is mounted read-only' test \
                "$(/usr/bin/plutil -extract "images.$dmg_test_image_index.writeable" raw -o - "$dmg_test_stage/images.plist")" = false
            dmg_test_entity_index=0
            while /usr/bin/plutil -extract "images.$dmg_test_image_index.system-entities.$dmg_test_entity_index" json -o /dev/null "$dmg_test_stage/images.plist" 2>/dev/null; do
                dmg_test_reported_mount="$(/usr/bin/plutil -extract "images.$dmg_test_image_index.system-entities.$dmg_test_entity_index.mount-point" raw -o - "$dmg_test_stage/images.plist" 2>/dev/null || true)"
                if [ "$dmg_test_reported_mount" = "$dmg_test_mount" ]; then dmg_test_found=yes; break; fi
                dmg_test_entity_index=$((dmg_test_entity_index + 1))
            done
        fi
        dmg_test_image_index=$((dmg_test_image_index + 1))
    done
    dmg_test_require 'Finder mount belongs to the exact requested image' test "$dmg_test_found" = yes
else
    /usr/bin/hdiutil attach -readonly -noautoopen -mountpoint "$dmg_test_mount" -plist "$dmg_test_image" > "$dmg_test_stage/mount.plist"
    dmg_test_mounted=yes
fi
dmg_test_app="$dmg_test_mount/Install PS1-2.app"
dmg_test_installer="$dmg_test_app/Contents/Resources/Installer"
dmg_test_target="$dmg_test_stage/Personal Applications/PS1-2.app"
dmg_test_require 'setup is a complete signed bundle' /usr/bin/codesign --verify --deep --strict "$dmg_test_app"
dmg_test_require 'image includes user instructions' test -r "$dmg_test_mount/Read Me.txt"
dmg_test_require 'bundle and source are read-only' test ! -w "$dmg_test_installer"
dmg_test_require 'does not contain the source toolchain entry point' test ! -e "$dmg_test_installer/build.sh"
dmg_test_require 'no source Git metadata' test ! -e "$dmg_test_installer/.git"
dmg_test_require 'payload has the current format' test "$(/usr/bin/plutil -extract PS12Distribution raw -o - "$dmg_test_installer/distribution.plist")" = prebuilt-v1
dmg_test_require 'setup executable is native arm64' test "$("$dmg_test_installer/payload/InspectMachO" "$dmg_test_app/Contents/MacOS/SetupWizard")" = arm64
# An invalid developer directory makes any accidental xcrun/lipo tool-shim
# invocation fail, without removing or changing the Mac's installed tools.
cd /
/usr/bin/env DEVELOPER_DIR="$dmg_test_stage/Unavailable Developer Tools" \
    /bin/bash "$dmg_test_installer/install.sh" --check --no-emulators \
    --destination "$dmg_test_stage/Personal Applications" > "$dmg_test_stage/preflight.log" 2>&1
dmg_test_require 'preflight did not publish an app' test ! -e "$dmg_test_target"
/usr/bin/env DEVELOPER_DIR="$dmg_test_stage/Unavailable Developer Tools" installer_dock_icon_dry_run=yes \
    /bin/bash "$dmg_test_installer/install.sh" --yes --no-emulators \
    --destination "$dmg_test_stage/Personal Applications" > "$dmg_test_stage/install.log" 2>&1
dmg_test_require 'real prebuilt install produces launcher without developer tools' test -x "$dmg_test_target/Contents/MacOS/PS12"
dmg_test_require 'installed signature validates' /usr/bin/codesign --verify --strict "$dmg_test_target"
dmg_test_require 'installed version matches distribution' test \
    "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$dmg_test_target/Contents/Info.plist")" = \
    "$(/usr/bin/plutil -extract Version raw -o - "$dmg_test_installer/distribution.plist")"
dmg_test_require 'installed binary exactly matches the payload' /usr/bin/cmp \
    "$dmg_test_target/Contents/MacOS/PS12" "$dmg_test_installer/payload/PS1-2.app/Contents/MacOS/PS12"
dmg_test_require 'installed launcher retains Gatekeeper assessment' /usr/bin/xattr -p com.apple.quarantine "$dmg_test_target"
dmg_test_require 'no PS1 emulator installed' test ! -e "$dmg_test_stage/Personal Applications/DuckStation.app"
dmg_test_require 'no PS2 emulator installed' test ! -e "$dmg_test_stage/Personal Applications/PCSX2.app"
dmg_test_require 'installation lock released' test ! -e "$dmg_test_stage/Personal Applications/.ps12-install-lock"
dmg_test_require 'runtime did not change the signed source' /usr/bin/codesign --verify --deep --strict "$dmg_test_app"
printf 'PASS: %s mounted-DMG assertions; isolated launcher install only, no emulator downloads or launches.\n' "$dmg_test_checks"
