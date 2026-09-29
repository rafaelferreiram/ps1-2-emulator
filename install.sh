#!/bin/bash
set -euo pipefail
installer_source="$(cd "$(dirname "$0")" && pwd)"
source "$installer_source/scripts/installer-lib.sh"

installer_usage() {
    printf '%s\n' 'PS1/2 — local install for macOS' \
        'Usage: bash install.sh [--check] [--no-emulators] [--yes] [--destination FOLDER]' \
        '  default: build the launcher and download missing DuckStation/PCSX2 into /Applications' \
        '  --check          diagnose only; do not download, build or change files' \
        '  --no-emulators   install the launcher only' \
        '  --yes            accept the plan without a prompt (does not accept licenses)' \
        '  --destination    an existing absolute folder, for example "$HOME/Applications"' \
        'Does not include BIOS or games. Does not install Rosetta or the Command Line Tools, and does not restart or open apps.'
}

installer_destination=/Applications
installer_check=no
installer_emulators=yes
installer_yes=no
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) installer_usage; exit 0 ;;
        --check) installer_check=yes ;;
        --no-emulators) installer_emulators=no ;;
        --yes) installer_yes=yes ;;
        --destination)
            [ "$#" -ge 2 ] || { installer_usage; exit 2; }
            installer_destination="$2"; shift ;;
        *) installer_error "Unknown option: $1"; exit 2 ;;
    esac
    shift
done

[ "$(/usr/bin/uname -s)" = Darwin ] || { installer_error 'This installer requires macOS.'; exit 1; }
[ "$EUID" -ne 0 ] || { installer_error 'Run it without sudo or root.'; exit 1; }
[ "$(/usr/bin/uname -m)" = arm64 ] || {
    installer_error 'The launcher requires Apple Silicon. If Terminal is using Rosetta, open it in native mode.'; exit 1;
}
installer_version_at_least "$(/usr/bin/sw_vers -productVersion)" 14.0 || {
    installer_error 'The launcher requires macOS 14 or later.'; exit 1;
}
/usr/bin/xcrun --find swiftc >/dev/null 2>&1 && /usr/bin/xcrun --show-sdk-path >/dev/null 2>&1 || {
    installer_error 'Install the Command Line Tools with: xcode-select --install. Finish that, then run this installer again.'; exit 1;
}
[[ "$installer_destination" = /* ]] && [ -d "$installer_destination" ] && [ ! -L "$installer_destination" ] || {
    installer_error 'The destination must be an existing absolute folder, not a shortcut or symlink.'; exit 1;
}
installer_destination="$(cd "$installer_destination" && pwd -P)"
case "$installer_destination" in /|"$HOME"|"$installer_source") installer_error 'Choose an applications folder, not a root, home or project folder.'; exit 1 ;; esac
[ -w "$installer_destination" ] || {
    installer_error 'Cannot write to the destination. Create ~/Applications and use --destination "$HOME/Applications". Do not use sudo.'; exit 1;
}
installer_target="$installer_destination/PS1-2.app"
if [ -e "$installer_target" ] || [ -L "$installer_target" ]; then
    installer_bundle_identity "$installer_target" local.rafael.centraldejogos || {
        installer_error "That destination does not look like this launcher: $installer_target"; exit 1;
    }
fi

printf '\nPS1/2 — install plan\nLauncher: build and install at %s\n' "$installer_target"
installer_duck=''; installer_pcsx=''
if [ "$installer_emulators" = yes ]; then
    installer_find_existing DuckStation.app com.github.stenzek.duckstation "$installer_destination"
    installer_duck="$existing_app"
    installer_find_existing PCSX2.app net.pcsx2.pcsx2 "$installer_destination"
    installer_pcsx="$existing_app"
    printf 'PS1: %s\nPS2: %s\n' "${installer_duck:-download official DuckStation and verify SHA256}" "${installer_pcsx:-download official stable PCSX2 and verify SHA256}"
else
    printf 'Emulators: do not install (--no-emulators).\n'
fi
printf 'Existing apps are kept; the previous launcher is backed up. BIOS, games and saves are not touched.\n'
printf 'PCSX2 may require Rosetta: accept the license only in Apple'\''s installer, if it asks when you open the app.\n'
if [ "$installer_check" = yes ]; then
    printf '\nCheck finished. Nothing was downloaded, built or changed; network, BIOS and gameplay were not tested.\n'
    exit 0
fi
if [ "$installer_yes" != yes ]; then
    if [ ! -t 0 ]; then installer_error 'Use an interactive Terminal, or --yes after reviewing the plan with --check.'; exit 1; fi
    read -r -p 'Continue? [y/N] ' installer_reply
    case "$installer_reply" in y|Y|yes|Yes) ;; *) printf 'Install cancelled.\n'; exit 0 ;; esac
fi
if [ -e "$installer_target" ]; then
    installer_launcher_closed
fi
installer_lock="$installer_destination/.ps12-install-lock"
/bin/mkdir "$installer_lock" 2>/dev/null || {
    installer_error "Another install or a leftover lock is at $installer_lock. Check it before trying again."; exit 1;
}
installer_stage=''
installer_pending_backup=''
installer_pending_destination=''
installer_cleanup() {
    local status=$?
    installer_rollback || true
    if [ -n "$installer_stage" ]; then
        # Keep only failure evidence. On success remove this exact mktemp path.
        if [ "$status" -eq 0 ]; then
            case "$installer_stage" in /private/tmp/ps12-install.??????) /bin/rm -rf -- "$installer_stage" ;; esac
        else printf 'Temporary files for diagnosis: %s\n' "$installer_stage" >&2; fi
    fi
    /bin/rmdir "$installer_lock" 2>/dev/null || true
}
trap installer_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
installer_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-install.XXXXXX)"
installer_move_tool="$installer_stage/MoveApp"
/usr/bin/xcrun swiftc -O -module-cache-path "$installer_source/cache" \
    "$installer_source/scripts/MoveApp.swift" -o "$installer_move_tool"
printf '\nBuilding the launcher…\n'
/bin/bash "$installer_source/build.sh" "$installer_stage/PS1-2.app"
installer_validate_bundle "$installer_stage/PS1-2.app" local.rafael.centraldejogos

# Prepare every missing app before publishing any app. A network/hash/build
# failure leaves the existing installation untouched.
installer_duck_download=''; installer_pcsx_download=''
if [ "$installer_emulators" = yes ]; then
    if [ -z "$installer_duck" ]; then
        installer_download_emulator duckstation "$installer_stage"
        installer_duck_download="$downloaded_app"
    fi
    if [ -z "$installer_pcsx" ]; then
        installer_download_emulator pcsx2 "$installer_stage"
        installer_pcsx_download="$downloaded_app"
    fi
fi
if [ -n "$installer_duck_download" ]; then
    installer_publish_app "$installer_duck_download" "$installer_destination/DuckStation.app" com.github.stenzek.duckstation no
fi
if [ -n "$installer_pcsx_download" ]; then
    installer_publish_app "$installer_pcsx_download" "$installer_destination/PCSX2.app" net.pcsx2.pcsx2 no
fi
if [ -e "$installer_target" ]; then installer_launcher_closed; fi
installer_publish_app "$installer_stage/PS1-2.app" "$installer_target" local.rafael.centraldejogos yes
installer_refresh_dock_icon "$installer_target" local.rafael.centraldejogos
printf '\nInstall finished. You do not need to restart the Mac.\n'
printf 'The Dock icon was updated. The current logo stays visible after you quit the launcher.\n'
printf 'Open DuckStation and PCSX2, set up your BIOS, libraries and controls. Then open the launcher:\n'
printf 'open "%s"\n' "$installer_target"
printf 'In the launcher, open Game folders (⌘,) and choose the PS1 and PS2 libraries on the Mac or on an external disk.\n'
printf 'The default remains /Volumes/Extreme SSD/Emulacao/{PS1,PS2}/Jogos. T/△ opens or reloads the catalog.\n'
printf 'Provide your own BIOS and games and configure the emulators. See README.md and docs/EMULADORES.md.\n'
