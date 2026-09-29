#!/bin/bash
set -euo pipefail
installer_source="$(cd "$(dirname "$0")" && pwd)"
source "$installer_source/scripts/installer-lib.sh"

installer_usage() {
    printf '%s\n' 'PS1/2 — instalação local para macOS' \
        'Uso: bash install.sh [--check] [--no-emulators] [--yes] [--destination PASTA]' \
        '  padrão: compilar central + baixar DuckStation/PCSX2 ausentes para /Applications' \
        '  --check          só diagnosticar; sem baixar, compilar ou modificar arquivos' \
        '  --no-emulators   instalar somente a central' \
        '  --yes            aceitar o plano sem prompt (não aceita licenças)' \
        '  --destination    pasta absoluta existente, ex.: "$HOME/Applications"' \
        'Não inclui BIOS/jogos. Não instala Rosetta/CLT nem reinicia/abre apps automaticamente.'
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
        *) installer_error "Opção desconhecida: $1"; exit 2 ;;
    esac
    shift
done

[ "$(/usr/bin/uname -s)" = Darwin ] || { installer_error 'Este instalador exige macOS.'; exit 1; }
[ "$EUID" -ne 0 ] || { installer_error 'Execute sem sudo/root.'; exit 1; }
[ "$(/usr/bin/uname -m)" = arm64 ] || {
    installer_error 'A central exige Apple Silicon. Se o Terminal usa Rosetta, abra-o em modo nativo.'; exit 1;
}
installer_version_at_least "$(/usr/bin/sw_vers -productVersion)" 14.0 || {
    installer_error 'A central exige macOS 14 ou posterior.'; exit 1;
}
/usr/bin/xcrun --find swiftc >/dev/null 2>&1 && /usr/bin/xcrun --show-sdk-path >/dev/null 2>&1 || {
    installer_error 'Instale as Command Line Tools com: xcode-select --install. Conclua e execute este instalador novamente.'; exit 1;
}
[[ "$installer_destination" = /* ]] && [ -d "$installer_destination" ] && [ ! -L "$installer_destination" ] || {
    installer_error 'Destino deve ser uma pasta absoluta existente, não um atalho/symlink.'; exit 1;
}
installer_destination="$(cd "$installer_destination" && pwd -P)"
case "$installer_destination" in /|"$HOME"|"$installer_source") installer_error 'Escolha uma pasta de aplicativos, não uma pasta raiz/pessoal/do projeto.'; exit 1 ;; esac
[ -w "$installer_destination" ] || {
    installer_error 'Sem escrita no destino. Crie ~/Applications e use --destination "$HOME/Applications". Não execute com sudo.'; exit 1;
}
installer_target="$installer_destination/PS1-2.app"
if [ -e "$installer_target" ] || [ -L "$installer_target" ]; then
    installer_bundle_identity "$installer_target" local.rafael.centraldejogos || {
        installer_error "O destino não parece nossa central: $installer_target"; exit 1;
    }
fi

printf '\nPS1/2 — plano de instalação\nCentral: compilar e instalar em %s\n' "$installer_target"
installer_duck=''; installer_pcsx=''
if [ "$installer_emulators" = yes ]; then
    installer_find_existing DuckStation.app com.github.stenzek.duckstation "$installer_destination"
    installer_duck="$existing_app"
    installer_find_existing PCSX2.app net.pcsx2.pcsx2 "$installer_destination"
    installer_pcsx="$existing_app"
    printf 'PS1: %s\nPS2: %s\n' "${installer_duck:-baixar DuckStation oficial e verificar SHA256}" "${installer_pcsx:-baixar PCSX2 estável oficial e verificar SHA256}"
else
    printf 'Emuladores: não instalar (--no-emulators).\n'
fi
printf 'Apps existentes serão preservados; a central anterior terá backup. BIOS, jogos e saves não serão tocados.\n'
printf 'PCSX2 pode exigir Rosetta: aceite a licença somente no instalador da Apple, se solicitado ao abrir.\n'
if [ "$installer_check" = yes ]; then
    printf '\nDiagnóstico concluído. Nada foi baixado, compilado ou alterado; rede/BIOS/jogabilidade não foram testados.\n'
    exit 0
fi
if [ "$installer_yes" != yes ]; then
    if [ ! -t 0 ]; then installer_error 'Use um Terminal interativo ou --yes após revisar o plano com --check.'; exit 1; fi
    read -r -p 'Prosseguir? [s/N] ' installer_reply
    case "$installer_reply" in s|S|sim|Sim) ;; *) printf 'Instalação cancelada.\n'; exit 0 ;; esac
fi
if [ -e "$installer_target" ]; then
    installer_launcher_closed
fi
installer_lock="$installer_destination/.ps12-install-lock"
/bin/mkdir "$installer_lock" 2>/dev/null || {
    installer_error "Outra instalação ou lock pendente: $installer_lock. Verifique antes de tentar novamente."; exit 1;
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
        else printf 'Arquivos temporários para diagnóstico: %s\n' "$installer_stage" >&2; fi
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
printf '\nCompilando a central…\n'
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
printf '\nInstalação concluída. Não é necessário reiniciar o Mac.\n'
printf 'O ícone do Dock foi atualizado. O logo atual permanece visível depois de encerrar a central.\n'
printf 'Abra DuckStation e PCSX2, configure suas BIOS, bibliotecas e controles. Depois abra a central:\n'
printf 'open "%s"\n' "$installer_target"
printf 'Na central, abra Pastas de jogos (⌘,) e escolha as bibliotecas PS1 e PS2 no Mac ou em um disco externo.\n'
printf 'O padrão continua /Volumes/Extreme SSD/Emulacao/{PS1,PS2}/Jogos. T/△ abre ou atualiza o catálogo.\n'
printf 'Forneça suas BIOS e jogos e configure os emuladores. Veja README.md e docs/EMULADORES.md.\n'
