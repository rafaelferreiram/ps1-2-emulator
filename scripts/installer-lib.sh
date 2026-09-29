#!/bin/bash
# Shared by install.sh and offline fixture tests. Sourcing has no side effects.

installer_error() { printf 'ERROR: %s\n' "$*" >&2; return 1; }
installer_plist() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

installer_version_at_least() {
    local have="$1" need="$2" h n i
    [[ "$have" =~ ^[0-9]+(\.[0-9]+){0,2}$ && "$need" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
    for i in 1 2 3; do
        h="${have%%.*}"; n="${need%%.*}"
        [ "$((10#$h))" -gt "$((10#$n))" ] && return 0
        [ "$((10#$h))" -lt "$((10#$n))" ] && return 1
        if [[ "$have" == *.* ]]; then have="${have#*.}"; else have=0; fi
        if [[ "$need" == *.* ]]; then need="${need#*.}"; else need=0; fi
    done
    return 0
}

installer_release_config() {
    case "$1" in
        duckstation)
            release_repository=stenzek/duckstation
            release_endpoint=https://api.github.com/repos/stenzek/duckstation/releases/tags/latest
            release_app_name=DuckStation.app
            release_bundle_id=com.github.stenzek.duckstation ;;
        pcsx2)
            release_repository=PCSX2/pcsx2
            release_endpoint=https://api.github.com/repos/PCSX2/pcsx2/releases/latest
            release_app_name=PCSX2.app
            release_bundle_id=net.pcsx2.pcsx2 ;;
        *) installer_error 'Unrecognized emulator.'; return 1 ;;
    esac
}

# All values come from one captured response, preventing mixed release metadata.
# No eval, shell code from the network, unauthenticated checksum fallback or tokens.
installer_select_asset() {
    local key="$1" metadata="$2" index=0 name expected found=0 digest
    installer_release_config "$key" || return 1
    [ "$(installer_plist "$metadata" draft)" = false ] &&
        [ "$(installer_plist "$metadata" prerelease)" = false ] || {
        installer_error 'The API did not return a public stable release.'; return 1;
    }
    release_tag="$(installer_plist "$metadata" tag_name)" || return 1
    case "$key" in
        duckstation)
            [ "$release_tag" = latest ] || return 1
            expected=duckstation-mac-release.zip ;;
        pcsx2)
            [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
            expected="pcsx2-$release_tag-macos-Qt.tar.xz" ;;
    esac
    while [ "$index" -lt 128 ] && name="$(installer_plist "$metadata" "assets.$index.name")"; do
        if [ "$name" = "$expected" ]; then
            [ "$found" -eq 0 ] || { installer_error 'Duplicate macOS package in the API response.'; return 1; }
            release_url="$(installer_plist "$metadata" "assets.$index.browser_download_url")" || return 1
            [ "$release_url" = "https://github.com/$release_repository/releases/download/$release_tag/$expected" ] || {
                installer_error 'The package URL does not match the official repository.'; return 1;
            }
            digest="$(installer_plist "$metadata" "assets.$index.digest")" || return 1
            [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || {
                installer_error 'SHA256 missing or invalid; automatic download stopped.'; return 1;
            }
            release_sha256="${digest#sha256:}"
            release_filename="$expected"
            found=1
        fi
        index=$((index + 1))
    done
    [ "$found" -eq 1 ] || { installer_error 'The expected macOS package was not found.'; return 1; }
}

installer_verify_sha256() {
    local actual
    [[ "$2" =~ ^[a-f0-9]{64}$ ]] || return 1
    actual="$(/usr/bin/shasum -a 256 "$1")" || return 1
    [ "${actual%% *}" = "$2" ] || { installer_error 'SHA256 does not match the published value. Nothing from this package will be installed.'; return 1; }
}

installer_bundle_identity() {
    local app="$1" expected="$2" executable
    [ -d "$app" ] && [ ! -L "$app" ] || return 1
    [ "$(installer_plist "$app/Contents/Info.plist" CFBundleIdentifier)" = "$expected" ] || return 1
    executable="$(installer_plist "$app/Contents/Info.plist" CFBundleExecutable)" || return 1
    [[ "$executable" =~ ^[A-Za-z0-9_.+-]+$ ]] || return 1
    [ -x "$app/Contents/MacOS/$executable" ]
}

installer_validate_bundle() {
    local app="$1" expected="$2" minimum
    installer_bundle_identity "$app" "$expected" || { installer_error "Unexpected or incomplete bundle: $app"; return 1; }
    /usr/bin/codesign --verify --strict "$app" || return 1
    minimum="$(installer_plist "$app/Contents/Info.plist" LSMinimumSystemVersion)" || minimum=''
    if [ -n "$minimum" ]; then
        installer_version_at_least "$(/usr/bin/sw_vers -productVersion)" "$minimum" || {
            installer_error "This package requires macOS $minimum or later."; return 1;
        }
    fi
}

installer_archive_paths_safe() {
    # libarchive also rejects traversal when extracting. Inspect names first,
    # after the exact archive bytes have passed the official SHA256 check.
    /usr/bin/awk '
        /^\// || /\\/ { exit 1 }
        { count=split($0, parts, "/"); for (i=1; i<=count; i++) if (parts[i]=="..") exit 1 }
    ' "$1"
}

installer_download_emulator() {
    local key="$1" stage="$2" metadata archive extracted listing candidate count=0 stamp
    installer_release_config "$key" || return 1
    metadata="$stage/$key-release.json"
    printf '\nChecking the official release: %s\n' "$release_endpoint"
    /usr/bin/curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 60 --retry 2 --max-filesize 2097152 \
        --output "$metadata" "$release_endpoint" || return 1
    installer_select_asset "$key" "$metadata" || return 1
    archive="$stage/$release_filename"
    printf 'Downloading %s (%s)\n%s\n' "$release_app_name" "$release_tag" "$release_url"
    /usr/bin/curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 900 --retry 2 --max-filesize 314572800 \
        --output "$archive" "$release_url" || return 1
    installer_verify_sha256 "$archive" "$release_sha256" || return 1
    listing="$stage/$key-archive.txt"
    /usr/bin/tar -tf "$archive" > "$listing" || return 1
    installer_archive_paths_safe "$listing" || { installer_error 'Invalid path inside the downloaded archive.'; return 1; }
    extracted="$stage/$key-extracted"
    /bin/mkdir "$extracted" || return 1
    /usr/bin/tar -xf "$archive" -C "$extracted" || return 1
    downloaded_app=''
    while IFS= read -r candidate; do
        downloaded_app="$candidate"
        count=$((count + 1))
    done < <(/usr/bin/find "$extracted" -type d -name '*.app' -prune -print)
    [ "$count" -eq 1 ] || { installer_error 'The package did not contain exactly one app.'; return 1; }
    installer_validate_bundle "$downloaded_app" "$release_bundle_id" || return 1
    # curl is not a browser: explicitly preserve normal Gatekeeper assessment
    # for these downloaded apps. Never clear quarantine or re-sign upstream apps.
    stamp="$(printf '%x' "$(/bin/date +%s)")"
    /usr/bin/xattr -w com.apple.quarantine "0083;$stamp;PS12Installer;" "$downloaded_app" || return 1
    printf 'SHA256 and bundle integrity checked: %s\n' "$release_app_name"
}

installer_find_existing() {
    local name="$1" identity="$2" destination="$3" directory candidate
    existing_app=''
    for directory in "$destination" /Applications "$HOME/Applications"; do
        candidate="$directory/$name"
        if [ -e "$candidate" ] || [ -L "$candidate" ]; then
            installer_bundle_identity "$candidate" "$identity" || {
                installer_error "An unexpected or incomplete app is already at $candidate. Review it manually."; return 1;
            }
            existing_app="$candidate"
            return 0
        fi
    done
}

installer_launcher_closed() {
    local output status
    if output="$(/usr/bin/pgrep -x PS12 2>&1)"; then
        installer_error 'Quit only the PS1/2 launcher (⌘Q) and run this again. No app will be force-quit.'
        return 1
    else status=$?; fi
    [ "$status" -eq 1 ] && [ -z "$output" ] || {
        installer_error 'Could not check whether the launcher is open. Install stopped for safety.'; return 1;
    }
}

installer_move_exclusive() {
    [ -n "${installer_move_tool:-}" ] && [ -x "$installer_move_tool" ] || {
        installer_error 'The publish tool did not compile.'; return 1;
    }
    "$installer_move_tool" "$1" "$2"
}

installer_rollback() {
    if [ -n "${installer_pending_backup:-}" ] && [ -e "$installer_pending_backup" ]; then
        if [ ! -e "$installer_pending_destination" ] && [ ! -L "$installer_pending_destination" ]; then
            if installer_move_exclusive "$installer_pending_backup" "$installer_pending_destination"; then
                printf 'Previous version restored: %s\n' "$installer_pending_destination" >&2
            else installer_error "Restore the backup manually: $installer_pending_backup"; return 1; fi
        else
            printf 'Backup kept: %s\n' "$installer_pending_backup" >&2
        fi
    fi
    installer_pending_backup=''; installer_pending_destination=''
}

installer_publish_app() {
    local source="$1" destination="$2" identity="$3" replace="$4" container name staging backup=''
    container="$(/usr/bin/dirname "$destination")"; name="$(/usr/bin/basename "$destination")"
    installer_validate_bundle "$source" "$identity" || return 1
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        installer_bundle_identity "$destination" "$identity" || return 1
        if [ "$replace" != yes ]; then
            printf 'Kept, already installed: %s\n' "$destination"
            return 0
        fi
    fi
    staging="$(/usr/bin/mktemp -d "$container/.ps12-stage.XXXXXX")" || return 1
    # Copy beside the final destination so publishing is a same-volume rename.
    /usr/bin/ditto "$source" "$staging/$name" || { installer_error "Incomplete copy kept at $staging"; return 1; }
    installer_validate_bundle "$staging/$name" "$identity" || return 1
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        installer_bundle_identity "$destination" "$identity" || return 1
        [ "$replace" = yes ] || { installer_error 'The destination appeared during install; nothing was overwritten.'; return 1; }
        backup="$(/usr/bin/mktemp -d "$container/.ps12-backup.XXXXXX")" || return 1
        # Set recovery state before moving the old app, including for SIGINT.
        installer_pending_destination="$destination"
        installer_pending_backup="$backup/$name"
        installer_move_exclusive "$destination" "$backup/$name" || return 1
        printf 'Backup of the previous launcher: %s\n' "$backup/$name"
    fi
    if ! installer_move_exclusive "$staging/$name" "$destination"; then
        installer_rollback || true
        installer_error "Install failed. Prepared copy: $staging"; return 1
    fi
    installer_pending_backup=''; installer_pending_destination=''
    /bin/rmdir "$staging" || true
    printf 'Installed: %s\n' "$destination"
}

# Other copies of the same bundle id (backups, Trash) keep the previous Dock
# bitmap. Launch Services returns that bitmap after the app quits.
installer_bundle_copies() {
    local identity="$1" lsregister path
    lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    [ -x "$lsregister" ] || return 0
    "$lsregister" -dump 2>/dev/null | /usr/bin/awk -v id="$identity" '
        /^path:/ {
            line = $0
            sub(/^path:[[:space:]]*/, "", line)
            sub(/[[:space:]]+\(0x[0-9a-fA-F]+\)$/, "", line)
            path = line
        }
        $0 ~ "^identifier:[[:space:]]+" id "$" && path != "" { print path }
    '
}

installer_refresh_dock_icon() {
    local app="$1" identity="$2" lsregister copy resolved parent
    lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    [ -d "$app" ] || return 1
    parent="$(/usr/bin/dirname "$app")"
    app="$(cd "$parent" && /bin/pwd -P)/$(/usr/bin/basename "$app")"
    while IFS= read -r copy; do
        [ -n "$copy" ] || continue
        parent="$(/usr/bin/dirname "$copy")"
        if [ -d "$parent" ]; then
            resolved="$(cd "$parent" && /bin/pwd -P)/$(/usr/bin/basename "$copy")"
        else
            resolved="$copy"
        fi
        [ "$resolved" = "$app" ] && continue
        if [ "${installer_dock_icon_dry_run:-no}" = yes ]; then
            printf 'unregister %s\n' "$resolved"
        elif [ -x "$lsregister" ]; then
            "$lsregister" -u "$resolved" >/dev/null 2>&1 || true
        fi
    done < <(installer_bundle_copies "$identity")
    if [ "${installer_dock_icon_dry_run:-no}" = yes ]; then
        printf 'register %s\n' "$app"
        return 0
    fi
    [ -x "$lsregister" ] && "$lsregister" -f "$app" >/dev/null 2>&1 || true
    # The Dock keeps the previous image until IconServices and Dock restart.
    /bin/rm -rf -- "$HOME/Library/Caches/com.apple.iconservices.store"
    /usr/bin/killall iconservicesagent >/dev/null 2>&1 || true
    if [ "${installer_restart_dock:-yes}" = yes ]; then
        /usr/bin/killall Dock >/dev/null 2>&1 || true
    fi
}
