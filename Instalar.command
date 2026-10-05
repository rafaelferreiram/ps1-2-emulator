#!/bin/bash

# These small wrappers use fixed system paths in production. Tests source this
# file and replace functions; no environment variable can redirect an installer.
ps12_bootstrap_repository() {
    local entry="${BASH_SOURCE[0]}" parent link hops=0
    # A Finder alias resolves before invocation; a shell symlink needs resolving
    # here so its neighbours are looked up beside the real script, not the link.
    while [ -L "$entry" ]; do
        hops=$((hops + 1))
        [ "$hops" -le 40 ] || return 1
        parent="$(cd -- "$(dirname -- "$entry")" && pwd -P)" || return 1
        link="$(/usr/bin/readlink "$entry")" || return 1
        case "$link" in /*) entry="$link" ;; *) entry="$parent/$link" ;; esac
    done
    (cd -- "$(dirname -- "$entry")" && pwd -P)
}
ps12_bootstrap_uname() { /usr/bin/uname "$@"; }
ps12_bootstrap_uid() { /usr/bin/id -u; }
ps12_bootstrap_version() { /usr/bin/sw_vers -productVersion; }
ps12_bootstrap_interactive() { [ -t 0 ]; }
ps12_bootstrap_read() { IFS= read -r "$1"; }
ps12_bootstrap_run_install() { local source="$1"; shift; /bin/bash "$source/install.sh" "$@"; }
ps12_bootstrap_make_stage() { /usr/bin/mktemp -d /private/tmp/ps12-setup.XXXXXX; }
ps12_bootstrap_install_tools() { /usr/bin/xcode-select --install; }

ps12_bootstrap_check_source() {
    local source="$1"
    if [ ! -f "$source/scripts/source-check.sh" ] || [ ! -r "$source/scripts/source-check.sh" ]; then
        printf 'ERRO: falta scripts/source-check.sh.\nPasta reconhecida: %s\nBaixe e extraia o ZIP completo; mantenha Instalar.command dentro da pasta do projeto.\n' "$source" >&2
        return 1
    fi
    source "$source/scripts/source-check.sh" || return 1
    ps12_source_check "$source"
}

ps12_bootstrap_tools_ready() {
    local developer_path compiler sdk
    developer_path="$(/usr/bin/xcode-select -p 2>/dev/null)" || return 1
    [ -d "$developer_path" ] || return 1
    compiler="$(/usr/bin/xcrun --no-cache --find swiftc 2>/dev/null)" && [ -x "$compiler" ] &&
        sdk="$(/usr/bin/xcrun --no-cache --sdk macosx --show-sdk-path 2>/dev/null)" &&
        [ -d "$sdk/System/Library/Frameworks/AppKit.framework" ]
}

ps12_bootstrap_preflight() {
    local system architecture version major uid
    system="$(ps12_bootstrap_uname -s)" || return 1
    [ "$system" = Darwin ] || { printf 'Este instalador requer macOS.\n' >&2; return 1; }
    uid="$(ps12_bootstrap_uid)" || return 1
    [ "$uid" != 0 ] || { printf 'Abra o instalador sem sudo e sem usar root.\n' >&2; return 1; }
    architecture="$(ps12_bootstrap_uname -m)" || return 1
    [ "$architecture" = arm64 ] || {
        printf 'É necessário um Mac Apple Silicon em modo nativo. Desative “Abrir usando Rosetta” no Terminal, se estiver ativo.\n' >&2
        return 1
    }
    version="$(ps12_bootstrap_version)" || return 1
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { printf 'Não foi possível verificar a versão do macOS.\n' >&2; return 1; }
    major="${version%%.*}"
    [ "${#major}" -le 3 ] && (( 10#$major >= 14 )) || {
        printf 'É necessário macOS 14 ou mais recente. Versão encontrada: %s\n' "$version" >&2
        return 1
    }
}

ps12_bootstrap_ensure_tools() {
    local bootstrap_reply
    if ps12_bootstrap_tools_ready; then return 0; fi
    printf '\nO assistente precisa do compilador Swift e do SDK do macOS fornecidos pela Apple.\n'
    printf 'As Command Line Tools são gratuitas; a janela da Apple informa o download e pede a sua autorização.\n'
    printf 'Não instalamos Rosetta, não aceitamos licenças e não usamos sudo automaticamente.\n'
    if ! ps12_bootstrap_interactive; then
        printf 'Abra Instalar.command no Terminal para autorizar as ferramentas da Apple. Nenhum download foi solicitado.\n' >&2
        return 1
    fi
    printf 'Deseja abrir agora o instalador oficial das Command Line Tools? [s/N] '
    if ! ps12_bootstrap_read bootstrap_reply; then
        printf '\nEntrada encerrada. Instalação cancelada; nenhum download foi solicitado.\n'
        return 1
    fi
    case "$bootstrap_reply" in s|S|sim|Sim|SIM|y|Y|yes|Yes) ;; *)
        printf 'Instalação cancelada. Nenhum download foi solicitado.\n'; return 1 ;;
    esac
    if ! ps12_bootstrap_install_tools; then
        printf 'A solicitação à Apple não foi concluída. Se as ferramentas já estiverem sendo instaladas, aguarde; caso contrário, cancele e revise a mensagem acima.\n' >&2
    fi
    while :; do
        printf '\nConclua a instalação na janela da Apple. Depois pressione Enter para verificar novamente, ou digite C para cancelar: '
        if ! ps12_bootstrap_read bootstrap_reply; then
            printf '\nEntrada encerrada. Execute este instalador novamente quando as ferramentas estiverem prontas.\n'
            return 1
        fi
        case "$bootstrap_reply" in c|C|cancelar|Cancelar|q|Q|n|N)
            printf 'Instalação do PS1/2 cancelada. Uma instalação já iniciada pela Apple é independente.\n'; return 1 ;;
        esac
        if ps12_bootstrap_tools_ready; then return 0; fi
        printf 'O compilador ou o SDK ainda não está disponível. Aguarde a conclusão; não solicitaremos outro download.\n'
    done
}

ps12_bootstrap_prepare_bundle() {
    local source="$1" stage="$2" bundle="$3"
    ps12_bootstrap_check_source "$source" || return 1
    /bin/mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$stage/module-cache" || return 1
    /bin/cp "$source/scripts/SetupInfo.plist" "$bundle/Contents/Info.plist" || return 1
    /bin/cp "$source/docs/images/icon.png" "$bundle/Contents/Resources/icon.png" || return 1
    /usr/bin/plutil -lint "$bundle/Contents/Info.plist" >/dev/null
}

ps12_bootstrap_compile() {
    local source="$1" executable="$2" module_cache="$3" log="$4"
    /usr/bin/xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
        -framework AppKit -framework SwiftUI -module-cache-path "$module_cache" \
        "$source/scripts/SetupWizard.swift" -o "$executable" >"$log" 2>&1
}

ps12_bootstrap_run_wizard() { "$1" "$2"; }

ps12_bootstrap_cleanup_success() {
    local stage="$1"
    # Only this exact mktemp template is eligible. Never accept an arbitrary root,
    # a symlink, or a path supplied through a command-line/environment override.
    case "$stage" in /private/tmp/ps12-setup.??????)
        [ ! -L "$stage" ] && [ -d "$stage" ] || return 1
        /bin/rm -rf -- "$stage" ;;
    *) printf 'Pasta temporária inesperada; preservada por segurança: %s\n' "$stage" >&2; return 1 ;;
    esac
}

ps12_bootstrap_main() {
    local source stage bundle executable status
    source="$(ps12_bootstrap_repository)" || { printf 'Não foi possível localizar o projeto.\n' >&2; return 1; }
    # CLI mode is the backend verbatim, including its exit status. In particular,
    # --check never compiles the assistant or asks to install dependencies.
    if [ "$#" -gt 0 ]; then
        ps12_bootstrap_check_source "$source" || return 1
        if ps12_bootstrap_run_install "$source" "$@"; then return 0; else status=$?; return "$status"; fi
    fi
    printf '\nPS1/2 — Assistente de instalação\n'
    printf 'Vamos abrir uma janela para revisar o plano antes de instalar qualquer app.\n'
    printf 'BIOS, jogos e saves não serão baixados nem alterados.\n'
    ps12_bootstrap_preflight || return 1
    ps12_bootstrap_check_source "$source" || return 1
    printf 'Pasta do instalador: %s\n' "$source"
    ps12_bootstrap_ensure_tools || return 1
    stage="$(ps12_bootstrap_make_stage)" || { printf 'Não foi possível criar a pasta temporária.\n' >&2; return 1; }
    case "$stage" in /private/tmp/ps12-setup.??????) ;; *) printf 'Pasta temporária inesperada: %s\n' "$stage" >&2; return 1 ;; esac
    bundle="$stage/Instalar PS1-2.app"
    executable="$bundle/Contents/MacOS/SetupWizard"
    if ! ps12_bootstrap_prepare_bundle "$source" "$stage" "$bundle"; then
        printf 'Preparação incompleta. Diagnóstico preservado em: %s\n' "$stage" >&2
        return 1
    fi
    printf '\nPreparando a janela do assistente… A primeira compilação pode demorar um pouco.\n'
    if ps12_bootstrap_compile "$source" "$executable" "$stage/module-cache" "$stage/setup-build.log"; then
        :
    else
        status=$?
        printf 'Não foi possível compilar o assistente (código %s).\nLeia o diagnóstico: %s/setup-build.log\n' "$status" "$stage" >&2
        return "$status"
    fi
    printf 'Assistente pronto. Continue na janela “PS1/2 · Instalação”.\n'
    if ps12_bootstrap_run_wizard "$executable" "$source" >"$stage/setup-session.log" 2>&1; then
        if ! ps12_bootstrap_cleanup_success "$stage"; then
            printf 'O assistente terminou, mas a pasta temporária foi preservada: %s\n' "$stage" >&2
        fi
        return 0
    else
        status=$?
        printf '\nO assistente encerrou com código %s. Nenhuma nova tentativa será iniciada automaticamente.\nDiagnóstico preservado em: %s/setup-session.log\n' "$status" "$stage" >&2
        return "$status"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    ps12_bootstrap_main "$@"
    exit "$?"
fi
