#!/bin/bash
# Offline portability fixtures. Compiler and signing commands are mocked; no
# application is launched or installed and no network connection is made.
set -euo pipefail
portable_test_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
portable_test_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-portable-tests.XXXXXX)"
portable_test_fixture="$portable_test_stage/Fonte com espaços e acentuação"
portable_test_command_log="$portable_test_stage/commands.log"
portable_test_output="$portable_test_stage/output.log"
portable_test_checks=0
portable_test_generated=()

portable_cleanup() {
    local status=$? item
    for item in "${portable_test_generated[@]}"; do
        case "$item" in /private/tmp/ps12-build-work.??????|/private/tmp/ps12-build.??????)
            if [ -d "$item" ] && [ ! -L "$item" ] && [ -O "$item" ]; then
                /bin/chmod -R u+w "$item"
                /bin/rm -r -- "$item"
            fi ;;
        esac
    done
    case "$portable_test_stage" in /private/tmp/ps12-portable-tests.??????)
        if [ -d "$portable_test_stage" ] && [ ! -L "$portable_test_stage" ]; then
            /bin/chmod -R u+w "$portable_test_stage"
            /bin/rm -r -- "$portable_test_stage"
        fi ;;
    esac
    return "$status"
}
trap portable_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
portable_require() {
    local description="$1"; shift
    if ! "$@"; then
        printf 'FAIL: %s\n' "$description" >&2
        [ ! -f "$portable_test_output" ] || /bin/cat "$portable_test_output" >&2
        exit 1
    fi
    portable_test_checks=$((portable_test_checks + 1))
}

# Copy only the distributable inputs, without Git or any local build artifacts.
/bin/mkdir -p "$portable_test_fixture/scripts" "$portable_test_stage/unrelated cwd" "$portable_test_stage/Apps pessoais"
while IFS= read -r portable_relative || [ -n "$portable_relative" ]; do
    case "$portable_relative" in ''|\#*) continue ;; esac
    case "$portable_relative" in /*|..|../*|*/../*|*/..) printf 'Invalid fixture manifest path.\n' >&2; exit 1 ;; esac
    /bin/mkdir -p "$portable_test_fixture/$(/usr/bin/dirname "$portable_relative")"
    /bin/cp "$portable_test_source/$portable_relative" "$portable_test_fixture/$portable_relative"
done < "$portable_test_source/scripts/required-files.txt"
for portable_relative in build.sh scripts/source-check.sh scripts/required-files.txt; do
    /bin/cp "$portable_test_source/$portable_relative" "$portable_test_fixture/$portable_relative"
done
/bin/chmod -R a-w "$portable_test_fixture"
portable_require 'fixture is actually read-only for this user' test ! -w "$portable_test_fixture"
portable_require 'ZIP fixture has no Git metadata' test ! -e "$portable_test_fixture/.git"

# Exported shell functions intercept only the expensive/compiler/signature
# operations. Copies, permissions, source validation and cleanup remain real.
xcrun() {
    local previous='' argument cache='' output='' icon=no
    for argument in "$@"; do
        case "$previous" in -module-cache-path) cache="$argument" ;; -o) output="$argument" ;; esac
        case "$argument" in */MakeIcon.swift) icon=yes ;; esac
        previous="$argument"
    done
    case "$cache" in /private/tmp/ps12-build-work.??????/module-cache) ;; *) return 91 ;; esac
    printf 'WORK:%s\n' "${cache%/module-cache}" >> "$portable_test_command_log"
    /bin/mkdir -p "$cache" || return 92
    printf 'compiler cache fixture\n' > "$cache/fixture"
    if [ "$icon" = yes ]; then
        [ "$output" = "${cache%/module-cache}/MakeIcon" ] || return 93
        printf '#!/bin/bash\nportable_icon_mock "$@"\n' > "$output"
        /bin/chmod +x "$output"
    else
        printf 'OUTPUT:%s\n' "$output" >> "$portable_test_command_log"
        if [ "${portable_test_failure:-}" = compile ]; then return 42; fi
        /bin/cp /usr/bin/true "$output"
    fi
}
portable_icon_mock() {
    case "$2" in /private/tmp/ps12-build-work.??????/AppIcon.iconset) ;; *) return 94 ;; esac
    printf 'icon fixture\n' > "$2/icon.png"
    printf 'icon fixture\n' > "$3"
}
sips() { [ "$1" = -Z ] && [ "$4" = --out ] && /bin/cp "$3" "$5"; }
codesign() { printf 'SIGN:%s\n' "$*" >> "$portable_test_command_log"; }
export -f xcrun portable_icon_mock sips codesign
export portable_test_command_log

portable_run() {
    : > "$portable_test_command_log"
    if (cd "$portable_test_stage/unrelated cwd" && /bin/bash "$portable_test_fixture/build.sh" "$@") > "$portable_test_output" 2>&1; then
        portable_status=0
    else portable_status=$?; fi
    portable_work="$(/usr/bin/sed -n 's/^WORK://p' "$portable_test_command_log" | /usr/bin/head -n 1)"
    if [ -n "$portable_work" ]; then portable_test_generated+=("$portable_work"); fi
}

portable_bundle="$portable_test_stage/Apps pessoais/PS1-2.app"
# An inherited variable must not be accepted as the transient cleanup target.
/bin/mkdir "$portable_test_stage/sentinel"
launcher_work="$portable_test_stage/sentinel" portable_run "$portable_bundle"
portable_require 'read-only source builds from unrelated cwd' test "$portable_status" -eq 0
portable_require 'caller-supplied destination is preserved literally' test -x "$portable_bundle/Contents/MacOS/PS12"
portable_require 'copied cover directories allow later owned staging cleanup' test -w "$portable_bundle/Contents/Resources/Covers/PS2"
for portable_resource in Creditos.txt Logo.png PS1Startup.gif PS2Startup.gif PS1Controller.png PS2Controller.png PS12ClassicIcon-v7.icns Covers/PS2/SLUS-21065.jpg; do
    portable_require "bundle includes $portable_resource" test -f "$portable_bundle/Contents/Resources/$portable_resource"
done
portable_require 'successful build removes its temporary compiler work' test ! -e "$portable_work"
portable_require 'environment cannot redirect temporary cleanup' test -d "$portable_test_stage/sentinel"
for portable_artifact in cache AppIcon.iconset MakeIcon; do
    portable_require "source remains free of $portable_artifact" test ! -e "$portable_test_fixture/$portable_artifact"
done

portable_run
portable_require 'default output works from a read-only moved source' test "$portable_status" -eq 0
portable_default_output="$(/usr/bin/sed -n 's/^OUTPUT://p' "$portable_test_command_log")"
case "$portable_default_output" in
    /private/tmp/ps12-build.??????/PS1-2.app/Contents/MacOS/PS12)
        portable_default_stage="${portable_default_output%/PS1-2.app/Contents/MacOS/PS12}"
        portable_test_generated+=("$portable_default_stage") ;;
    *) printf 'FAIL: default output path changed: %s\n' "$portable_default_output" >&2; exit 1 ;;
esac
portable_require 'default final app survives transient cleanup' test -x "$portable_default_output"
portable_require 'default build removes only its compiler work' test ! -e "$portable_work"

portable_test_failure=compile portable_run "$portable_test_stage/Failed app.app"
portable_require 'compiler exit status survives cleanup trap' test "$portable_status" -eq 42
portable_require 'failed compiler work remains available' test -f "$portable_work/module-cache/fixture"
portable_require 'failure tells user where diagnostics were preserved' /usr/bin/grep -Fq "$portable_work" "$portable_test_output"
portable_require 'failure happens before signing' test "$(/usr/bin/grep -c '^SIGN:' "$portable_test_command_log" || true)" -eq 0

# An incomplete extraction must fail before making an output bundle or starting
# any compiler. Restore write permission only on this temporary test fixture.
/bin/chmod u+w "$portable_test_fixture" "$portable_test_fixture/scripts"
/bin/mv "$portable_test_fixture/Info.plist" "$portable_test_stage/Info.plist"
portable_run "$portable_test_stage/Missing input.app"
portable_require 'missing required source is rejected' test "$portable_status" -ne 0
portable_require 'missing required source never invokes compiler' test ! -s "$portable_test_command_log"
portable_require 'missing required source creates no app output' test ! -e "$portable_test_stage/Missing input.app"
/bin/mv "$portable_test_fixture/scripts/source-check.sh" "$portable_test_stage/source-check.sh"
portable_run "$portable_test_stage/Missing validator.app"
portable_require 'missing validator is rejected before build' test "$portable_status" -ne 0
portable_require 'missing validator creates no app output' test ! -e "$portable_test_stage/Missing validator.app"
portable_require 'missing validator explains incomplete download' /usr/bin/grep -q 'download do projeto está incompleto' "$portable_test_output"
printf 'PASS: %s portable build assertions; no compilation, downloads, app execution or installation.\n' "$portable_test_checks"
