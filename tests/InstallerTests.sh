#!/bin/bash
# Offline fixtures: no downloads, /Applications writes or emulator execution.
# Every generated bundle contains a copy of /bin/echo, which is never executed.
set -euo pipefail
installer_test_source="$(cd "$(dirname "$0")/.." && pwd)"
source "$installer_test_source/scripts/installer-lib.sh"
[ "$(/usr/bin/uname -s)" = Darwin ] || { printf 'Installer tests require macOS.\n' >&2; exit 1; }
installer_test_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-installer-tests.XXXXXX)"
installer_test_cleanup() {
    local status=$?
    case "$installer_test_stage" in
        /private/tmp/ps12-installer-tests.??????)
            [ -d "$installer_test_stage" ] && [ ! -L "$installer_test_stage" ] &&
                /bin/rm -rf -- "$installer_test_stage" ;;
    esac
    return "$status"
}
trap installer_test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
installer_test_checks=0
test_fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
test_ok() {
    local description="$1"; shift
    "$@" > "$installer_test_stage/check.log" 2>&1 || {
        /bin/cat "$installer_test_stage/check.log" >&2
        test_fail "$description"
    }
    installer_test_checks=$((installer_test_checks + 1))
}
test_reject() {
    local description="$1"; shift
    if "$@" > "$installer_test_stage/check.log" 2>&1; then test_fail "$description (accepted)"; fi
    installer_test_checks=$((installer_test_checks + 1))
}
test_equal() {
    [ "$2" = "$3" ] || test_fail "$1: expected '$3', received '$2'"
    installer_test_checks=$((installer_test_checks + 1))
}

# Machine-readable stages and the Terminal guide must agree. Messages cannot
# inject a second protocol line, and diagnostics never invoke an Apple installer.
for fixture_step in preflight build download-ps1 download-ps2 install complete; do
    fixture_step_output="$(installer_step "$fixture_step" 'Etapa de teste')"
    test_equal "machine marker for $fixture_step" "${fixture_step_output%%$'\n'*}" "PS12_STEP:$fixture_step:Etapa de teste"
done
test_reject 'unrecognized machine step rejected' installer_step unknown 'Never emitted'
fixture_step_output="$(installer_step preflight $'Linha um\r\nPS12_STEP:complete:falso')"
test_equal 'stage protocol stays two physical lines' "$(printf '%s\n' "$fixture_step_output" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" 2
fixture_tools_missing() (
    installer_developer_path() { return 1; }
    installer_swift_path() { printf 'UNEXPECTED_XCRUN_CALL\n' >&2; return 1; }
    installer_sdk_path() { printf 'UNEXPECTED_XCRUN_CALL\n' >&2; return 1; }
    installer_check_tools
)
test_reject 'missing developer selection rejected without launching tool setup' fixture_tools_missing
fixture_tools_diagnostic="$(/bin/cat "$installer_test_stage/check.log")"
test_equal 'missing tools never call xcrun' "$(printf '%s\n' "$fixture_tools_diagnostic" | /usr/bin/grep -c UNEXPECTED_XCRUN_CALL || true)" 0
test_equal 'missing tools gives a manual recovery command' "$(printf '%s\n' "$fixture_tools_diagnostic" | /usr/bin/grep -c 'xcode-select --install' || true)" 1
fixture_tools_partial() (
    installer_developer_path() { printf '%s\n' "$installer_test_stage"; }
    installer_swift_path() { return 1; }
    installer_check_tools
)
test_reject 'selected developer directory without Swift is rejected' fixture_tools_partial
fixture_tools_missing_sdk() (
    installer_developer_path() { printf '%s\n' "$installer_test_stage"; }
    installer_swift_path() { printf '/bin/echo\n'; }
    installer_sdk_path() { return 1; }
    installer_check_tools
)
test_reject 'missing SDK is rejected without attempting a build' fixture_tools_missing_sdk

# Constants below are fixture inputs, never network-provided shell commands.
fixture_hash=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
fixture_duck_url=https://github.com/stenzek/duckstation/releases/download/latest/duckstation-mac-release.zip
fixture_pcsx_url=https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-macos-Qt.tar.xz
fixture_release="$installer_test_stage/release.json"
fixture_asset() {
    printf '{"name":"%s","browser_download_url":"%s","digest":%s}' "$1" "$2" "$3"
}
fixture_metadata() {
    printf '{"draft":%s,"prerelease":%s,"tag_name":"%s","assets":[%s]}\n' \
        "$1" "$2" "$3" "$4" > "$fixture_release"
}
fixture_duck_asset="$(fixture_asset duckstation-mac-release.zip "$fixture_duck_url" "\"sha256:$fixture_hash\"")"
fixture_pcsx_asset="$(fixture_asset pcsx2-v2.8.2-macos-Qt.tar.xz "$fixture_pcsx_url" "\"sha256:$fixture_hash\"")"
test_ok 'same macOS version' installer_version_at_least 14.0 14.0
test_ok 'missing minor and patch treated as zero' installer_version_at_least 14 14.0.0
test_ok 'newer macOS major' installer_version_at_least 27.0 14.0
test_ok 'numeric version comparison' installer_version_at_least 14.2.10 14.2.9
test_reject 'older macOS minor' installer_version_at_least 14.1 14.2
test_reject 'older macOS major' installer_version_at_least 13.6.8 14
test_reject 'malformed current version' installer_version_at_least 14.bad 14.0
test_reject 'malformed required version' installer_version_at_least 14.0 14.0.0.1
test_reject 'unknown emulator' installer_release_config unknown
fixture_metadata false false latest "$fixture_duck_asset"
test_ok 'official DuckStation release metadata' installer_select_asset duckstation "$fixture_release"
test_equal 'DuckStation URL' "$release_url" "$fixture_duck_url"
test_equal 'DuckStation digest' "$release_sha256" "$fixture_hash"
test_equal 'DuckStation bundle identity' "$release_bundle_id" com.github.stenzek.duckstation
test_equal 'DuckStation filename' "$release_filename" duckstation-mac-release.zip
fixture_metadata false false v2.8.2 "$fixture_pcsx_asset"
test_ok 'official PCSX2 stable release metadata' installer_select_asset pcsx2 "$fixture_release"
test_equal 'PCSX2 URL' "$release_url" "$fixture_pcsx_url"
test_equal 'PCSX2 digest' "$release_sha256" "$fixture_hash"
test_equal 'PCSX2 bundle identity' "$release_bundle_id" net.pcsx2.pcsx2
test_equal 'PCSX2 tag' "$release_tag" v2.8.2
test_equal 'PCSX2 keeps verified upstream name, not invented universal suffix' "$release_filename" pcsx2-v2.8.2-macos-Qt.tar.xz
fixture_metadata false false v2.8.2 "$(fixture_asset pcsx2-v2.8.2-macos-universal-Qt.tar.xz "$fixture_pcsx_url" "\"sha256:$fixture_hash\"")"
test_reject 'unverified universal filename cannot replace official asset' installer_select_asset pcsx2 "$fixture_release"
for fixture_kind in duckstation pcsx2; do
    if [ "$fixture_kind" = duckstation ]; then
        fixture_tag=latest; fixture_asset_json="$fixture_duck_asset"
        fixture_name=duckstation-mac-release.zip; fixture_url="$fixture_duck_url"
    else
        fixture_tag=v2.8.2; fixture_asset_json="$fixture_pcsx_asset"
        fixture_name=pcsx2-v2.8.2-macos-Qt.tar.xz; fixture_url="$fixture_pcsx_url"
    fi
    fixture_metadata true false "$fixture_tag" "$fixture_asset_json"
    test_reject "$fixture_kind draft" installer_select_asset "$fixture_kind" "$fixture_release"
    fixture_metadata false true "$fixture_tag" "$fixture_asset_json"
    test_reject "$fixture_kind prerelease" installer_select_asset "$fixture_kind" "$fixture_release"
    fixture_metadata false false unexpected-tag "$fixture_asset_json"
    test_reject "$fixture_kind unexpected tag" installer_select_asset "$fixture_kind" "$fixture_release"
    fixture_metadata false false "$fixture_tag" "$fixture_asset_json,$fixture_asset_json"
    test_reject "$fixture_kind duplicate asset" installer_select_asset "$fixture_kind" "$fixture_release"
    fixture_metadata false false "$fixture_tag" ''
    test_reject "$fixture_kind missing asset" installer_select_asset "$fixture_kind" "$fixture_release"
    fixture_metadata false false "$fixture_tag" "$(fixture_asset unexpected.zip "$fixture_url" "\"sha256:$fixture_hash\"")"
    test_reject "$fixture_kind incorrect filename" installer_select_asset "$fixture_kind" "$fixture_release"
    for fixture_bad_url in "http://${fixture_url#https://}" \
        "https://github.com.attacker.invalid/${fixture_url#https://github.com/}" "${fixture_url}?other=asset"; do
        fixture_metadata false false "$fixture_tag" "$(fixture_asset "$fixture_name" "$fixture_bad_url" "\"sha256:$fixture_hash\"")"
        test_reject "$fixture_kind noncanonical URL" installer_select_asset "$fixture_kind" "$fixture_release"
    done
    for fixture_bad_digest in null '"sha256:abc"' '"sha512:abc"' '"sha256:BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"'; do
        fixture_metadata false false "$fixture_tag" "$(fixture_asset "$fixture_name" "$fixture_url" "$fixture_bad_digest")"
        test_reject "$fixture_kind absent/malformed digest" installer_select_asset "$fixture_kind" "$fixture_release"
    done
    fixture_metadata false false "$fixture_tag" "{\"name\":\"$fixture_name\",\"browser_download_url\":\"$fixture_url\"}"
    test_reject "$fixture_kind omitted digest field" installer_select_asset "$fixture_kind" "$fixture_release"
done
printf 'not json\n' > "$fixture_release"
test_reject 'invalid release JSON' installer_select_asset duckstation "$fixture_release"
printf abc > "$installer_test_stage/bytes.dat"
test_ok 'real SHA256 of fixture bytes' installer_verify_sha256 "$installer_test_stage/bytes.dat" "$fixture_hash"
test_reject 'mismatched SHA256' installer_verify_sha256 "$installer_test_stage/bytes.dat" 0000000000000000000000000000000000000000000000000000000000000000
test_reject 'malformed expected SHA256' installer_verify_sha256 "$installer_test_stage/bytes.dat" abc
test_reject 'missing download file' installer_verify_sha256 "$installer_test_stage/absent.dat" "$fixture_hash"
fixture_listing="$installer_test_stage/archive.txt"
printf '%s\n' './DuckStation.app/' './DuckStation.app/Contents/Info.plist' 'assets/a..b' > "$fixture_listing"
test_ok 'safe relative archive listing' installer_archive_paths_safe "$fixture_listing"
for fixture_bad_path in '/tmp/escape' '../escape' 'App/../escape' 'App/a/../../escape' 'App\..\escape'; do
    printf '%s\n' 'App/Contents/Info.plist' "$fixture_bad_path" > "$fixture_listing"
    test_reject "unsafe archive path: $fixture_bad_path" installer_archive_paths_safe "$fixture_listing"
done

fixture_bundle() {
    local target="$1" identity="$2" version="$3"
    /bin/mkdir -p "$target/Contents/MacOS" "$target/Contents/Resources"
    /bin/cp /bin/echo "$target/Contents/MacOS/PS12Fixture"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict>' '<key>CFBundlePackageType</key><string>APPL</string>' \
        '<key>CFBundleExecutable</key><string>PS12Fixture</string>' \
        "<key>CFBundleIdentifier</key><string>$identity</string>" \
        "<key>CFBundleVersion</key><string>$version</string>" \
        '<key>LSMinimumSystemVersion</key><string>14.0</string>' \
        '</dict></plist>' > "$target/Contents/Info.plist"
    printf 'fixture version %s\n' "$version" > "$target/Contents/Resources/version.txt"
}
fixture_sign() { /usr/bin/codesign --force --sign - "$1"; }
fixture_identity_app="$installer_test_stage/Identity.app"
fixture_bundle "$fixture_identity_app" local.ps12.offlinefixture 1
test_ok 'fake bundle identity' installer_bundle_identity "$fixture_identity_app" local.ps12.offlinefixture
test_reject 'wrong bundle identity' installer_bundle_identity "$fixture_identity_app" local.ps12.wrong
/bin/ln -s "$fixture_identity_app" "$installer_test_stage/Shortcut.app"
test_reject 'symlink bundle rejected' installer_bundle_identity "$installer_test_stage/Shortcut.app" local.ps12.offlinefixture
/usr/bin/plutil -replace CFBundleExecutable -string ../PS12Fixture "$fixture_identity_app/Contents/Info.plist"
test_reject 'executable traversal rejected' installer_bundle_identity "$fixture_identity_app" local.ps12.offlinefixture
/usr/bin/plutil -replace CFBundleExecutable -string Missing "$fixture_identity_app/Contents/Info.plist"
test_reject 'missing executable rejected' installer_bundle_identity "$fixture_identity_app" local.ps12.offlinefixture
/usr/bin/plutil -replace CFBundleExecutable -string PS12Fixture "$fixture_identity_app/Contents/Info.plist"
test_reject 'unsigned fixture rejected' installer_validate_bundle "$fixture_identity_app" local.ps12.offlinefixture
test_ok 'sign disposable local fixture' fixture_sign "$fixture_identity_app"
test_ok 'signed fixture validates' installer_validate_bundle "$fixture_identity_app" local.ps12.offlinefixture
/usr/bin/plutil -replace LSMinimumSystemVersion -string 99.0 "$fixture_identity_app/Contents/Info.plist"
test_ok 'sign future-macOS fixture' fixture_sign "$fixture_identity_app"
test_reject 'future macOS requirement rejected' installer_validate_bundle "$fixture_identity_app" local.ps12.offlinefixture

fixture_apps="$installer_test_stage/Applications"
/bin/mkdir "$fixture_apps"
installer_move_tool="$installer_test_stage/MoveApp"
test_ok 'compile exclusive publication helper in temp' /usr/bin/xcrun swiftc -O \
    -module-cache-path "$installer_test_stage/SwiftCache" "$installer_test_source/scripts/MoveApp.swift" -o "$installer_move_tool"
fixture_move_source="$installer_test_stage/exclusive-source"
fixture_move_destination="$installer_test_stage/exclusive-destination"
/bin/mkdir "$fixture_move_source" "$fixture_move_destination"
printf 'source\n' > "$fixture_move_source/marker.txt"
printf 'destination\n' > "$fixture_move_destination/marker.txt"
test_reject 'exclusive move rejects existing directory' installer_move_exclusive "$fixture_move_source" "$fixture_move_destination"
test_ok 'exclusive rejection preserves source' test -f "$fixture_move_source/marker.txt"
test_equal 'exclusive rejection preserves destination' "$(/bin/cat "$fixture_move_destination/marker.txt")" destination
test_ok 'exclusive move creates no nested source' test ! -e "$fixture_move_destination/exclusive-source"
test_ok 'exclusive move to empty path' installer_move_exclusive "$fixture_move_source" "$installer_test_stage/exclusive-result"
test_ok 'successful exclusive move removes old source' test ! -e "$fixture_move_source"
test_ok 'successful exclusive move retains marker' test -f "$installer_test_stage/exclusive-result/marker.txt"
fixture_old="$installer_test_stage/OldCentral.app"
fixture_new="$installer_test_stage/NewCentral.app"
fixture_bundle "$fixture_old" local.rafael.centraldejogos 1
fixture_bundle "$fixture_new" local.rafael.centraldejogos 2
test_ok 'sign old central fixture' fixture_sign "$fixture_old"
test_ok 'sign new central fixture' fixture_sign "$fixture_new"
test_ok 'publish central to isolated destination' installer_publish_app "$fixture_old" "$fixture_apps/PS1-2.app" local.rafael.centraldejogos yes
test_ok 'published central signature' installer_validate_bundle "$fixture_apps/PS1-2.app" local.rafael.centraldejogos
test_equal 'initial central version' "$(installer_plist "$fixture_apps/PS1-2.app/Contents/Info.plist" CFBundleVersion)" 1
test_ok 'update central with backup' installer_publish_app "$fixture_new" "$fixture_apps/PS1-2.app" local.rafael.centraldejogos yes
test_equal 'updated central version' "$(installer_plist "$fixture_apps/PS1-2.app/Contents/Info.plist" CFBundleVersion)" 2
fixture_backup_count=0
fixture_backup=''
while IFS= read -r fixture_candidate; do
    fixture_backup="$fixture_candidate/PS1-2.app"
    fixture_backup_count=$((fixture_backup_count + 1))
done < <(/usr/bin/find "$fixture_apps" -type d -name '.ps12-backup.*' -prune -print)
test_equal 'exactly one central backup' "$fixture_backup_count" 1
test_ok 'backup central signature' installer_validate_bundle "$fixture_backup" local.rafael.centraldejogos
test_equal 'backup preserves original version' "$(installer_plist "$fixture_backup/Contents/Info.plist" CFBundleVersion)" 1

fixture_rollback="$installer_test_stage/rollback"
/bin/mkdir "$fixture_rollback"
/usr/bin/ditto "$fixture_old" "$fixture_rollback/Backup.app"
installer_pending_backup="$fixture_rollback/Backup.app"
installer_pending_destination="$fixture_rollback/Restored.app"
test_ok 'rollback restores backup when destination absent' installer_rollback
test_ok 'restored backup signature' installer_validate_bundle "$fixture_rollback/Restored.app" local.rafael.centraldejogos
test_ok 'restored backup moved, not duplicated' test ! -e "$fixture_rollback/Backup.app"
test_equal 'rollback clears pending backup' "$installer_pending_backup" ''
test_equal 'rollback clears pending destination' "$installer_pending_destination" ''
/usr/bin/ditto "$fixture_new" "$fixture_rollback/Backup.app"
installer_pending_backup="$fixture_rollback/Backup.app"
installer_pending_destination="$fixture_rollback/Restored.app"
test_ok 'rollback preserves backup when destination already exists' installer_rollback
test_equal 'rollback does not replace existing destination' "$(installer_plist "$fixture_rollback/Restored.app/Contents/Info.plist" CFBundleVersion)" 1
test_equal 'rollback leaves conflicting backup intact' "$(installer_plist "$fixture_rollback/Backup.app/Contents/Info.plist" CFBundleVersion)" 2

# Inject only a publication rename failure, in a subshell. The real exclusive
# helper still performs backup and rollback moves; no production hook is needed.
fixture_failed_publish="$fixture_apps/RollbackCentral.app"
test_ok 'publish rollback fixture' installer_publish_app "$fixture_old" "$fixture_failed_publish" local.rafael.centraldejogos yes
fixture_publish_failure() (
    installer_move_exclusive() {
        case "$1" in "$fixture_apps"/.ps12-stage.*/*) return 1 ;; esac
        "$installer_move_tool" "$1" "$2"
    }
    installer_publish_app "$fixture_new" "$fixture_failed_publish" local.rafael.centraldejogos yes
)
test_reject 'publication rename failure is reported' fixture_publish_failure
test_ok 'publication failure restores signed old app' installer_validate_bundle "$fixture_failed_publish" local.rafael.centraldejogos
test_equal 'publication failure restores old version' "$(installer_plist "$fixture_failed_publish/Contents/Info.plist" CFBundleVersion)" 1

fixture_duck_old="$installer_test_stage/OldDuck.app"
fixture_duck_new="$installer_test_stage/NewDuck.app"
fixture_bundle "$fixture_duck_old" com.github.stenzek.duckstation 1
fixture_bundle "$fixture_duck_new" com.github.stenzek.duckstation 2
test_ok 'sign old emulator fixture' fixture_sign "$fixture_duck_old"
test_ok 'sign new emulator fixture' fixture_sign "$fixture_duck_new"
test_ok 'publish missing emulator fixture' installer_publish_app "$fixture_duck_old" "$fixture_apps/DuckStation.app" com.github.stenzek.duckstation no
test_ok 'preserve existing emulator' installer_publish_app "$fixture_duck_new" "$fixture_apps/DuckStation.app" com.github.stenzek.duckstation no
test_equal 'emulator keeps original version' "$(installer_plist "$fixture_apps/DuckStation.app/Contents/Info.plist" CFBundleVersion)" 1
test_ok 'find emulator in isolated destination' installer_find_existing DuckStation.app com.github.stenzek.duckstation "$fixture_apps"
test_equal 'existing emulator path' "$existing_app" "$fixture_apps/DuckStation.app"

# Alter a signed fixture; failure must never overwrite the installed app.
printf 'tampered\n' > "$fixture_new/Contents/Resources/version.txt"
test_reject 'tampered signature rejected' installer_validate_bundle "$fixture_new" local.rafael.centraldejogos
test_reject 'tampered source cannot publish' installer_publish_app "$fixture_new" "$fixture_apps/PS1-2.app" local.rafael.centraldejogos yes
test_ok 'installed central stays signed after failed update' installer_validate_bundle "$fixture_apps/PS1-2.app" local.rafael.centraldejogos
test_equal 'failed update preserves version' "$(installer_plist "$fixture_apps/PS1-2.app/Contents/Info.plist" CFBundleVersion)" 2
test_reject 'wrong source cannot replace central' installer_publish_app "$fixture_duck_new" "$fixture_apps/PS1-2.app" local.rafael.centraldejogos yes
test_equal 'wrong source leaves installed version' "$(installer_plist "$fixture_apps/PS1-2.app/Contents/Info.plist" CFBundleVersion)" 2
test_reject 'foreign destination app not overwritten' installer_publish_app "$fixture_duck_new" "$fixture_apps/PS1-2.app" com.github.stenzek.duckstation no
test_ok 'central valid after identity rejection' installer_validate_bundle "$fixture_apps/PS1-2.app" local.rafael.centraldejogos
fixture_dock_log="$installer_test_stage/dock-icon.log"
(
    installer_dock_icon_dry_run=yes
    installer_bundle_copies() {
        printf 'UNEXPECTED_COPY_SCAN\n'
    }
    installer_refresh_dock_icon "$fixture_apps/PS1-2.app" local.rafael.centraldejogos
) > "$fixture_dock_log"
test_ok 'registration targets only the installed bundle' /usr/bin/grep -Fxq "register $fixture_apps/PS1-2.app" "$fixture_dock_log"
test_equal 'registration emits exactly one action' "$(/usr/bin/wc -l < "$fixture_dock_log" | /usr/bin/tr -d ' ')" 1
test_reject 'registration never enumerates or unregisters other copies' /usr/bin/grep -Eq 'unregister|UNEXPECTED_COPY_SCAN' "$fixture_dock_log"
test_reject 'registration rejects a different bundle identity' installer_refresh_dock_icon "$fixture_apps/PS1-2.app" local.ps12.wrong
fixture_registration_source="$(/usr/bin/sed -n '/^installer_refresh_dock_icon()/,$p' "$installer_test_source/scripts/installer-lib.sh")"
test_equal 'registration contains no global cache deletion or killall' "$(printf '%s\n' "$fixture_registration_source" | /usr/bin/grep -Ec 'killall|/bin/rm|lsregister.*-u' || true)" 0
printf 'Installer offline tests: %s checks passed. No network, real apps or user data touched.\n' "$installer_test_checks"
