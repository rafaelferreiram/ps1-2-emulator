#!/bin/bash
set -uo pipefail
bootstrap_test_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
bootstrap_test_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-bootstrap-tests.XXXXXX)"
bootstrap_test_log="$bootstrap_test_stage/output.log"
bootstrap_test_generated=()
bootstrap_test_assertions=0

bootstrap_test_cleanup() {
    local item
    for item in "${bootstrap_test_generated[@]}"; do
        case "$item" in /private/tmp/ps12-setup.??????)
            if [ -d "$item" ] && [ ! -L "$item" ]; then /bin/rm -rf -- "$item"; fi ;;
        esac
    done
    case "$bootstrap_test_stage" in /private/tmp/ps12-bootstrap-tests.??????)
        [ ! -L "$bootstrap_test_stage" ] && /bin/rm -rf -- "$bootstrap_test_stage" ;;
    esac
}
trap bootstrap_test_cleanup EXIT

bootstrap_test_require() {
    local description="$1"; shift
    bootstrap_test_assertions=$((bootstrap_test_assertions + 1))
    if ! "$@"; then
        printf 'FAIL: %s\n' "$description" >&2
        /bin/cat "$bootstrap_test_log" >&2
        exit 1
    fi
}
bootstrap_test_capture() {
    if "$@" >"$bootstrap_test_log" 2>&1; then bootstrap_status=0; else bootstrap_status=$?; fi
}

# Source guard: importing helpers must not run backend commands or open a GUI.
# If that guard ever regresses, --check still prevents installation side effects.
set -- --check
source "$bootstrap_test_source/Instalar.command"
set --
bootstrap_test_require 'helpers are available after source' declare -F ps12_bootstrap_main

ps12_bootstrap_repository() { printf '%s\n' '/private/tmp/Fonte com espaços/PS1-2'; }
ps12_bootstrap_uname() { if [ "$1" = -s ]; then printf '%s\n' "$bootstrap_os"; else printf '%s\n' "$bootstrap_arch"; fi; }
ps12_bootstrap_uid() { printf '%s\n' "$bootstrap_uid"; }
ps12_bootstrap_version() { printf '%s\n' "$bootstrap_version"; }
ps12_bootstrap_interactive() { return "$bootstrap_interactive"; }
ps12_bootstrap_read() {
    local answer="${bootstrap_answers[$bootstrap_read_count]-__EOF__}"
    bootstrap_read_count=$((bootstrap_read_count + 1))
    [ "$answer" != __EOF__ ] || return 1
    printf -v "$1" '%s' "$answer"
}
ps12_bootstrap_tools_ready() {
    local result="${bootstrap_ready_results[$bootstrap_ready_count]:-1}"
    bootstrap_ready_count=$((bootstrap_ready_count + 1))
    return "$result"
}
ps12_bootstrap_install_tools() {
    bootstrap_install_tools_count=$((bootstrap_install_tools_count + 1))
    return "$bootstrap_tools_request_status"
}
ps12_bootstrap_run_install() {
    bootstrap_backend_count=$((bootstrap_backend_count + 1))
    bootstrap_forwarded=("$@")
    return "$bootstrap_backend_status"
}
ps12_bootstrap_make_stage() { printf '%s\n' "$bootstrap_stage"; }
ps12_bootstrap_prepare_bundle() {
    bootstrap_prepare_count=$((bootstrap_prepare_count + 1))
    bootstrap_prepare_arguments=("$@")
    return "$bootstrap_prepare_status"
}
ps12_bootstrap_compile() {
    bootstrap_compile_count=$((bootstrap_compile_count + 1))
    bootstrap_compile_arguments=("$@")
    return "$bootstrap_compile_status"
}
ps12_bootstrap_run_wizard() {
    bootstrap_wizard_count=$((bootstrap_wizard_count + 1))
    bootstrap_wizard_arguments=("$@")
    printf 'Fixture diagnostic from wizard\n' >&2
    return "$bootstrap_wizard_status"
}

bootstrap_reset() {
    bootstrap_os=Darwin; bootstrap_arch=arm64; bootstrap_uid=501; bootstrap_version=14.0
    bootstrap_interactive=0; bootstrap_answers=(); bootstrap_read_count=0
    bootstrap_ready_results=(0); bootstrap_ready_count=0
    bootstrap_tools_request_status=0; bootstrap_install_tools_count=0
    bootstrap_backend_count=0; bootstrap_backend_status=0; bootstrap_forwarded=()
    bootstrap_prepare_count=0; bootstrap_prepare_status=0; bootstrap_prepare_arguments=()
    bootstrap_compile_count=0; bootstrap_compile_status=0; bootstrap_compile_arguments=()
    bootstrap_wizard_count=0; bootstrap_wizard_status=0; bootstrap_wizard_arguments=()
    bootstrap_stage=''
}
bootstrap_new_stage() {
    bootstrap_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-setup.XXXXXX)"
    bootstrap_test_generated+=("$bootstrap_stage")
}

bootstrap_reset
bootstrap_os=Linux; bootstrap_uid=0; bootstrap_ready_results=(1)
bootstrap_test_capture ps12_bootstrap_main --check --destination '/Applications/Apps pessoais'
bootstrap_test_require '--check forwards without bootstrap preflight' test "$bootstrap_status" -eq 0
bootstrap_test_require '--check invokes backend exactly once' test "$bootstrap_backend_count" -eq 1
bootstrap_test_require 'source containing spaces remains one literal argument' test "${bootstrap_forwarded[0]}" = '/private/tmp/Fonte com espaços/PS1-2'
bootstrap_test_require 'check flag is preserved' test "${bootstrap_forwarded[1]}" = --check
bootstrap_test_require 'destination with spaces is preserved' test "${bootstrap_forwarded[3]}" = '/Applications/Apps pessoais'
bootstrap_test_require '--check does not probe compilers' test "$bootstrap_ready_count" -eq 0
bootstrap_test_require '--check does not compile or open wizard' test "$((bootstrap_compile_count + bootstrap_wizard_count + bootstrap_install_tools_count))" -eq 0
bootstrap_backend_status=37
bootstrap_test_capture ps12_bootstrap_main --unknown
bootstrap_test_require 'CLI child failure status is preserved' test "$bootstrap_status" -eq 37
bootstrap_test_require 'unknown CLI arguments still belong to backend' test "${bootstrap_forwarded[1]}" = --unknown

for bootstrap_case in os root arch old malformed; do
    bootstrap_reset
    case "$bootstrap_case" in os) bootstrap_os=Linux ;; root) bootstrap_uid=0 ;; arch) bootstrap_arch=x86_64 ;; old) bootstrap_version=13.7 ;; malformed) bootstrap_version='unknown' ;; esac
    bootstrap_test_capture ps12_bootstrap_main
    bootstrap_test_require "unsupported preflight fails: $bootstrap_case" test "$bootstrap_status" -eq 1
    bootstrap_test_require "unsupported preflight has no tools or compile side effects: $bootstrap_case" test "$((bootstrap_ready_count + bootstrap_compile_count + bootstrap_install_tools_count))" -eq 0
done

bootstrap_reset; bootstrap_ready_results=(1); bootstrap_interactive=1
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'noninteractive missing tools fails without reading stdin' test "$bootstrap_read_count" -eq 0
bootstrap_test_require 'noninteractive missing tools never requests download' test "$bootstrap_install_tools_count" -eq 0

for bootstrap_answer in n '' __EOF__; do
    bootstrap_reset; bootstrap_ready_results=(1); bootstrap_answers=("$bootstrap_answer")
    bootstrap_test_capture ps12_bootstrap_main
    bootstrap_test_require 'refusal/default/EOF cancels missing tools' test "$bootstrap_status" -eq 1
    bootstrap_test_require 'refusal/default/EOF has no refusal loop' test "$bootstrap_read_count" -eq 1
    bootstrap_test_require 'refusal/default/EOF never requests tools' test "$bootstrap_install_tools_count" -eq 0
done

bootstrap_reset; bootstrap_ready_results=(1 1 0); bootstrap_answers=(s '' ''); bootstrap_new_stage
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'opt-in followed by completed Apple install continues' test "$bootstrap_status" -eq 0
bootstrap_test_require 'retry never requests a second Apple download' test "$bootstrap_install_tools_count" -eq 1
bootstrap_test_require 'checks again only after explicit input' test "$bootstrap_ready_count" -eq 3
bootstrap_test_require 'wizard is compiled once after tools ready' test "$bootstrap_compile_count" -eq 1
bootstrap_test_require 'wizard source argument preserves spaces' test "${bootstrap_wizard_arguments[1]}" = '/private/tmp/Fonte com espaços/PS1-2'
bootstrap_test_require 'wizard executable is inside temporary app bundle' test "${bootstrap_wizard_arguments[0]}" = "$bootstrap_stage/Instalar PS1-2.app/Contents/MacOS/SetupWizard"
bootstrap_test_require 'compiler cache stays in temporary staging' test "${bootstrap_compile_arguments[2]}" = "$bootstrap_stage/module-cache"
bootstrap_test_require 'successful wizard removes exactly its temporary stage' test ! -e "$bootstrap_stage"

bootstrap_reset; bootstrap_ready_results=(1); bootstrap_answers=(s __EOF__); bootstrap_tools_request_status=9
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'Apple request failure plus EOF does not loop' test "$bootstrap_read_count" -eq 2
bootstrap_test_require 'Apple request failure never starts compiler' test "$bootstrap_compile_count" -eq 0
bootstrap_test_require 'Apple request failure status is explained' /usr/bin/grep -q 'solicitação à Apple não foi concluída' "$bootstrap_test_log"

bootstrap_reset; bootstrap_ready_results=(1); bootstrap_answers=(s c)
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'explicit cancel during Apple wait does not compile' test "$bootstrap_compile_count" -eq 0
bootstrap_test_require 'explicit cancel during Apple wait stops reading' test "$bootstrap_read_count" -eq 2

bootstrap_reset; bootstrap_new_stage; bootstrap_compile_status=42
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'compiler failure status is propagated' test "$bootstrap_status" -eq 42
bootstrap_test_require 'compiler failure does not run wizard' test "$bootstrap_wizard_count" -eq 0
bootstrap_test_require 'compiler diagnostics staging is preserved' test -d "$bootstrap_stage"

bootstrap_reset; bootstrap_new_stage; bootstrap_prepare_status=7
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'incomplete repo is explicit failure' test "$bootstrap_status" -eq 1
bootstrap_test_require 'incomplete repo never starts compiler' test "$bootstrap_compile_count" -eq 0
bootstrap_test_require 'incomplete repo retains diagnostic stage' test -d "$bootstrap_stage"

bootstrap_reset; bootstrap_new_stage; bootstrap_wizard_status=23
bootstrap_test_capture ps12_bootstrap_main
bootstrap_test_require 'wizard failure status is propagated' test "$bootstrap_status" -eq 23
bootstrap_test_require 'wizard failure is not retried automatically' test "$bootstrap_wizard_count" -eq 1
bootstrap_test_require 'wizard failure preserves diagnostics' test -d "$bootstrap_stage"
bootstrap_test_require 'wizard stderr survives closing its window' /usr/bin/grep -q 'Fixture diagnostic from wizard' "$bootstrap_stage/setup-session.log"
bootstrap_test_require 'wizard failure points to saved session log' /usr/bin/grep -q 'setup-session.log' "$bootstrap_test_log"

bootstrap_test_capture ps12_bootstrap_cleanup_success "$bootstrap_test_stage"
bootstrap_test_require 'cleanup refuses paths outside exact setup template' test "$bootstrap_status" -eq 1
bootstrap_test_require 'refused cleanup preserves test directory' test -d "$bootstrap_test_stage"
printf 'PASS: %s bootstrap assertions; no compiler, GUI, downloads or installed apps invoked.\n' "$bootstrap_test_assertions"
