#!/bin/bash
set -euo pipefail
layout_source="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
layout_stage="$(/usr/bin/mktemp -d /private/tmp/ps12-layout-tests.XXXXXX)"
layout_fixture="$layout_stage/Outro usuário/Downloads/PS1-2 (edição nova)"
layout_checks=0
layout_cleanup() {
    case "$layout_stage" in /private/tmp/ps12-layout-tests.??????)
        if [ -d "$layout_stage" ] && [ ! -L "$layout_stage" ] && [ -O "$layout_stage" ]; then
            /bin/chmod -R u+w "$layout_stage"
            /bin/rm -r -- "$layout_stage"
        fi ;;
    esac
}
trap layout_cleanup EXIT
layout_require() {
    local message="$1"; shift
    if ! "$@"; then printf 'FAIL: %s\n' "$message" >&2; exit 1; fi
    layout_checks=$((layout_checks + 1))
}
source "$layout_source/scripts/source-check.sh"
/bin/mkdir -p "$layout_fixture" "$layout_stage/Apps pessoais" "$layout_stage/atalhos"
while IFS= read -r layout_relative || [ -n "$layout_relative" ]; do
    case "$layout_relative" in ''|\#*) continue ;; esac
    /bin/mkdir -p "$layout_fixture/$(/usr/bin/dirname "$layout_relative")"
    /bin/cp "$layout_source/$layout_relative" "$layout_fixture/$layout_relative"
done < "$layout_source/scripts/required-files.txt"
layout_require 'complete distribution validates outside Git' ps12_source_check "$layout_fixture"
layout_require 'fixture has no Git metadata' test ! -e "$layout_fixture/.git"
/bin/chmod -R a-w "$layout_fixture"
layout_require 'fixture is genuinely read-only' test ! -w "$layout_fixture"
layout_run() {
    if (cd / && /bin/bash "$1" --check --destination "$layout_stage/Apps pessoais") >"$layout_stage/check.log" 2>&1; then
        layout_status=0
    else layout_status=$?; fi
}
layout_run "$layout_fixture/Instalar.command"
layout_require 'real --check works with spaces, accents and unrelated cwd' test "$layout_status" -eq 0
layout_require 'read-only check did not create source cache' test ! -e "$layout_fixture/cache"
layout_require 'read-only check did not publish an app' test ! -e "$layout_stage/Apps pessoais/PS1-2.app"
/bin/ln -s '../Outro usuário/Downloads/PS1-2 (edição nova)/Instalar.command' "$layout_stage/atalhos/Instalar aqui.command"
layout_run "$layout_stage/atalhos/Instalar aqui.command"
layout_require 'relative shell symlink resolves the actual project directory' test "$layout_status" -eq 0

# A moved/renamed complete ZIP still works; no personal path is retained.
/bin/chmod u+w "$layout_fixture"
/bin/mv "$layout_fixture" "$layout_stage/PS1-2 renomeado"
layout_fixture="$layout_stage/PS1-2 renomeado"
/bin/chmod a-w "$layout_fixture"
layout_run "$layout_fixture/Instalar.command"
layout_require 'renaming the source does not break the next invocation' test "$layout_status" -eq 0
/bin/chmod u+w "$layout_fixture/scripts"
/bin/mv "$layout_fixture/scripts/installer-lib.sh" "$layout_stage/installer-lib.sh"
layout_run "$layout_fixture/Instalar.command"
layout_require 'missing backend library fails during source validation' test "$layout_status" -ne 0
layout_require 'missing library is named clearly' /usr/bin/grep -Fq 'scripts/installer-lib.sh' "$layout_stage/check.log"
layout_require 'missing library does not produce raw shell file-not-found error' test "$(/usr/bin/grep -c 'No such file or directory' "$layout_stage/check.log" || true)" -eq 0
layout_require 'incomplete ZIP never reaches Apple tool lookup' test "$(/usr/bin/grep -c 'Ferramentas Apple' "$layout_stage/check.log" || true)" -eq 0
/bin/mv "$layout_stage/installer-lib.sh" "$layout_fixture/scripts/installer-lib.sh"
/bin/mv "$layout_fixture/scripts/source-check.sh" "$layout_stage/source-check.sh"
layout_run "$layout_fixture/Instalar.command"
layout_require 'standalone/missing-validator startup fails helpfully' test "$layout_status" -ne 0
layout_require 'missing validator recovery mentions full ZIP' /usr/bin/grep -Fq 'ZIP completo' "$layout_stage/check.log"
/bin/mv "$layout_stage/source-check.sh" "$layout_fixture/scripts/source-check.sh"
/bin/mv "$layout_fixture/scripts/required-files.txt" "$layout_stage/required-files.txt"
layout_run "$layout_fixture/Instalar.command"
layout_require 'missing manifest fails explicitly' test "$layout_status" -ne 0
layout_require 'missing manifest is named' /usr/bin/grep -Fq 'scripts/required-files.txt' "$layout_stage/check.log"
printf 'PASS: %s source-layout assertions; real read-only checks only, no installation or downloads.\n' "$layout_checks"
