#!/bin/bash
# Offline integration fixtures only: no network, /Applications writes, real app
# execution or LaunchServices registration. Developer tools build fixtures first;
# every installer subprocess then receives an unusable developer-tool directory.
set -euo pipefail
prebuilt_source="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
[ "$(/usr/bin/uname -s)" = Darwin ] && [ "$(/usr/bin/uname -m)" = arm64 ] || {
    printf 'Prebuilt installer tests require Apple Silicon macOS.\n' >&2; exit 1;
}
prebuilt_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-prebuilt-tests.XXXXXX)"
prebuilt_cleanup() {
    local status=$?
    case "$prebuilt_stage" in /private/tmp/ps12-prebuilt-tests.??????)
        if [ -d "$prebuilt_stage" ] && [ ! -L "$prebuilt_stage" ] && [ -O "$prebuilt_stage" ]; then
            /bin/chmod -R u+w "$prebuilt_stage"
            /bin/rm -r -- "$prebuilt_stage"
        fi ;;
    esac
    return "$status"
}
trap prebuilt_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
prebuilt_checks=0
prebuilt_require() {
    local description="$1"; shift
    if ! "$@"; then
        if [ -f "$prebuilt_stage/run.log" ]; then /bin/cat "$prebuilt_stage/run.log" >&2; fi
        printf 'FAIL: %s\n' "$description" >&2; exit 1
    fi
    prebuilt_checks=$((prebuilt_checks + 1))
}
prebuilt_fixture="$prebuilt_stage/Outro usuário/Install PS1-2.app/Contents/Resources/Installer"
prebuilt_apps="$prebuilt_stage/Apps pessoais"
/bin/mkdir -p "$prebuilt_fixture/scripts" "$prebuilt_fixture/payload" "$prebuilt_apps"
/bin/cp "$prebuilt_source/install.sh" "$prebuilt_fixture/install.sh"
/bin/cp "$prebuilt_source/scripts/installer-lib.sh" "$prebuilt_source/scripts/payload-check.sh" "$prebuilt_fixture/scripts/"
/usr/bin/plutil -create xml1 "$prebuilt_fixture/distribution.plist"
/usr/bin/plutil -insert PS12Distribution -string prebuilt-v1 "$prebuilt_fixture/distribution.plist"
for prebuilt_helper in MoveApp InspectMachO; do
    prebuilt_compile_flags=(-O)
    if [ "$prebuilt_helper" = InspectMachO ]; then prebuilt_compile_flags=(-O -parse-as-library); fi
    /usr/bin/xcrun swiftc "${prebuilt_compile_flags[@]}" -target arm64-apple-macosx14.0 \
        -module-cache-path "$prebuilt_stage/module-cache" \
        "$prebuilt_source/scripts/$prebuilt_helper.swift" -o "$prebuilt_fixture/payload/$prebuilt_helper"
    /usr/bin/codesign --force --sign - "$prebuilt_fixture/payload/$prebuilt_helper"
done
prebuilt_app="$prebuilt_fixture/payload/PS1-2.app"
/bin/mkdir -p "$prebuilt_app/Contents/MacOS" "$prebuilt_app/Contents/Resources"
# This copy is never executed as an app; it is a native Mach-O fixture only.
/bin/cp "$prebuilt_fixture/payload/MoveApp" "$prebuilt_app/Contents/MacOS/PS12Fixture"
/usr/bin/plutil -create xml1 "$prebuilt_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string local.rafael.centraldejogos "$prebuilt_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string PS12Fixture "$prebuilt_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$prebuilt_app/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$prebuilt_app/Contents/Info.plist"
printf 'signed fixture\n' > "$prebuilt_app/Contents/Resources/fixture.txt"
/usr/bin/codesign --force --sign - "$prebuilt_app"
prebuilt_run() {
    if (cd / && /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin \
        DEVELOPER_DIR="$prebuilt_stage/Unavailable-Xcode" \
        installer_distribution=source installer_arch_tool=/invalid/InspectMachO \
        installer_move_tool=/invalid/MoveApp installer_dock_icon_dry_run=yes \
        /bin/bash -x "$prebuilt_fixture/install.sh" --no-emulators --destination "$prebuilt_apps" "$@") \
        > "$prebuilt_stage/run.log" 2>&1; then prebuilt_status=0; else prebuilt_status=$?; fi
    prebuilt_require 'packaged execution never invokes developer tools' \
        test "$(/usr/bin/grep -Ec '^\+.*(/usr/bin/(xcrun|xcode-select|lipo)|(^| )swiftc( |$))' "$prebuilt_stage/run.log" || true)" -eq 0
}
prebuilt_no_writes() {
    prebuilt_require 'preflight creates no destination entries' \
        test "$(/usr/bin/find "$prebuilt_apps" -mindepth 1 -maxdepth 1 -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -eq 0
}
prebuilt_run --check
prebuilt_require 'valid package passes without developer tools or source files' test "$prebuilt_status" -eq 0
prebuilt_no_writes
prebuilt_require 'packaged fixture has no build script' test ! -e "$prebuilt_fixture/build.sh"
prebuilt_require 'packaged fixture has no source validator' test ! -e "$prebuilt_fixture/scripts/source-check.sh"
for prebuilt_missing in distribution.plist scripts/installer-lib.sh scripts/payload-check.sh payload/MoveApp payload/InspectMachO payload/PS1-2.app; do
    /bin/mv "$prebuilt_fixture/$prebuilt_missing" "$prebuilt_stage/held-component"
    prebuilt_run --check
    prebuilt_require "missing $prebuilt_missing is rejected" test "$prebuilt_status" -ne 0
    prebuilt_no_writes
    /bin/mv "$prebuilt_stage/held-component" "$prebuilt_fixture/$prebuilt_missing"
done
/usr/bin/plutil -replace PS12Distribution -string unknown "$prebuilt_fixture/distribution.plist"
prebuilt_run --check
prebuilt_require 'unknown payload format is rejected' test "$prebuilt_status" -ne 0
prebuilt_no_writes
/usr/bin/plutil -replace PS12Distribution -string prebuilt-v1 "$prebuilt_fixture/distribution.plist"
/bin/cp "$prebuilt_app/Contents/Resources/fixture.txt" "$prebuilt_stage/original-resource"
printf 'damaged resource\n' > "$prebuilt_app/Contents/Resources/fixture.txt"
prebuilt_run --check
prebuilt_require 'tampered bundle is rejected before installation' test "$prebuilt_status" -ne 0
prebuilt_no_writes
/bin/cp "$prebuilt_stage/original-resource" "$prebuilt_app/Contents/Resources/fixture.txt"
/bin/mv "$prebuilt_fixture/payload/MoveApp" "$prebuilt_stage/held-helper"
/bin/ln -s "$prebuilt_stage/held-helper" "$prebuilt_fixture/payload/MoveApp"
prebuilt_run --check
prebuilt_require 'external helper symlink is rejected' test "$prebuilt_status" -ne 0
prebuilt_no_writes
/bin/rm "$prebuilt_fixture/payload/MoveApp"
/bin/mv "$prebuilt_stage/held-helper" "$prebuilt_fixture/payload/MoveApp"
/usr/bin/plutil -replace LSMinimumSystemVersion -string 99.0 "$prebuilt_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$prebuilt_app"
prebuilt_run --check
prebuilt_require 'incompatible minimum macOS is rejected' test "$prebuilt_status" -ne 0
prebuilt_no_writes
/usr/bin/plutil -replace LSMinimumSystemVersion -string 14.0 "$prebuilt_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$prebuilt_app"
/bin/chmod -R a-w "$prebuilt_fixture"
prebuilt_require 'packaged source is read-only' test ! -w "$prebuilt_fixture"
prebuilt_run --check
prebuilt_require 'read-only DMG preflight passes' test "$prebuilt_status" -eq 0
prebuilt_no_writes
prebuilt_run --yes
prebuilt_require 'read-only prebuilt package installs without developer tools' test "$prebuilt_status" -eq 0
prebuilt_require 'only launcher is published' test -d "$prebuilt_apps/PS1-2.app"
prebuilt_require 'published fixture remains signed' /usr/bin/codesign --verify --strict "$prebuilt_apps/PS1-2.app"
prebuilt_require 'launcher retains Gatekeeper quarantine' /usr/bin/xattr -p com.apple.quarantine "$prebuilt_apps/PS1-2.app"
prebuilt_require 'installation releases its lock' test ! -e "$prebuilt_apps/.ps12-install-lock"
prebuilt_require 'precompiled source remains intact' test -x "$prebuilt_fixture/payload/MoveApp"
prebuilt_require 'installation reports completion' /usr/bin/grep -Fq 'PS12_STEP:complete:' "$prebuilt_stage/run.log"
printf 'PASS: %s prebuilt installer assertions. No downloads or real apps touched.\n' "$prebuilt_checks"
