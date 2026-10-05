#!/bin/bash
set -euo pipefail
installer_source="$(cd "$(dirname "$0")" && pwd)"
source "$installer_source/scripts/installer-lib.sh"

installer_usage() {
    printf '%s\n' 'PS1/2 — instalação guiada para macOS' \
        'Uso: bash install.sh [--check] [--no-emulators] [--yes] [--destination PASTA]' \
        '  padrão: compilar a central e baixar DuckStation/PCSX2 ausentes em /Applications' \
        '  --check          apenas verificar; não baixar, compilar ou alterar arquivos' \
        '  --no-emulators   instalar somente a central' \
        '  --yes            confirmar o plano sem pergunta (não aceita licenças)' \
        '  --destination    pasta absoluta já existente, por exemplo "$HOME/Applications"' \
        'Não inclui BIOS ou jogos. Não instala Rosetta/ferramentas Apple, não reinicia o Mac e não abre apps sozinho.'
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

installer_step preflight 'Verificando o Mac, as ferramentas Apple e a pasta de instalação'
[ "$(/usr/bin/uname -s)" = Darwin ] || { installer_error 'Este instalador exige macOS.'; exit 1; }
[ "$EUID" -ne 0 ] || { installer_error 'Execute sem sudo e sem root.'; exit 1; }
[ "$(/usr/bin/uname -m)" = arm64 ] || {
    installer_error 'A central exige Apple Silicon (M1 ou posterior). Se o Terminal estiver usando Rosetta, abra-o em modo nativo.'; exit 1;
}
installer_version_at_least "$(/usr/bin/sw_vers -productVersion)" 14.0 || {
    installer_error 'A central exige macOS 14 ou mais recente.'; exit 1;
}
installer_check_tools
[[ "$installer_destination" = /* ]] && [ -d "$installer_destination" ] && [ ! -L "$installer_destination" ] || {
    installer_error 'O destino deve ser uma pasta absoluta já existente, não um atalho ou link simbólico.'; exit 1;
}
installer_destination="$(cd "$installer_destination" && pwd -P)"
case "$installer_destination" in /|"$HOME"|"$installer_source") installer_error 'Escolha uma pasta de aplicativos, não a raiz do disco, a pasta pessoal ou a pasta do projeto.'; exit 1 ;; esac
[ -w "$installer_destination" ] || {
    installer_error 'Sem permissão para gravar no destino. Crie ~/Applications e use --destination "$HOME/Applications". Não use sudo.'; exit 1;
}
installer_target="$installer_destination/PS1-2.app"
if [ -e "$installer_target" ] || [ -L "$installer_target" ]; then
    installer_bundle_identity "$installer_target" local.rafael.centraldejogos || {
        installer_error "O app nesse destino não corresponde à central: $installer_target"; exit 1;
    }
fi

printf '\nPS1/2 — pronto para começar\nCentral: compilar e instalar em %s\n' "$installer_target"
installer_duck=''; installer_pcsx=''
if [ "$installer_emulators" = yes ]; then
    installer_find_existing DuckStation.app com.github.stenzek.duckstation "$installer_destination"
    installer_duck="$existing_app"
    installer_find_existing PCSX2.app net.pcsx2.pcsx2 "$installer_destination"
    installer_pcsx="$existing_app"
    printf 'PS1: %s\nPS2: %s\n' "${installer_duck:-baixar DuckStation oficial e verificar SHA-256}" "${installer_pcsx:-baixar PCSX2 estável oficial e verificar SHA-256}"
else
    printf 'Emuladores: não instalar (--no-emulators).\n'
fi
printf 'Emuladores existentes serão preservados. A central anterior terá backup. BIOS, jogos e saves não serão alterados.\n'
printf 'Se um emulador precisar de Rosetta, o macOS poderá pedir ao abri-lo; você decide e aceita a licença diretamente com a Apple.\n'
if [ "$installer_check" = yes ]; then
    installer_step preflight 'Verificação concluída; nada foi baixado, compilado ou alterado'
    printf 'Rede, BIOS e execução dos jogos não foram testadas. Para instalar, execute novamente sem --check.\n'
    exit 0
fi
if [ "$installer_yes" != yes ]; then
    if [ ! -t 0 ]; then installer_error 'Use um Terminal interativo ou --yes depois de revisar o plano com --check.'; exit 1; fi
    read -r -p 'Instalar agora? [s/N] ' installer_reply
    case "$installer_reply" in s|S|sim|Sim|y|Y|yes|Yes) ;; *) printf 'Instalação cancelada. Nada foi alterado.\n'; exit 0 ;; esac
fi
if [ -e "$installer_target" ]; then
    installer_launcher_closed
fi
installer_lock="$installer_destination/.ps12-install-lock"
/bin/mkdir "$installer_lock" 2>/dev/null || {
    installer_error "Há outra instalação ou um bloqueio anterior em $installer_lock. Confira antes de tentar novamente."; exit 1;
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
installer_step build 'Preparando e compilando sua central PS1/2'
/usr/bin/xcrun swiftc -O -module-cache-path "$installer_source/cache" \
    "$installer_source/scripts/MoveApp.swift" -o "$installer_move_tool" || {
    installer_error 'Não foi possível compilar a ferramenta de instalação. Confira as mensagens das ferramentas Apple acima.'; exit 1;
}
/bin/bash "$installer_source/build.sh" "$installer_stage/PS1-2.app" || {
    installer_error 'A compilação da central falhou. A instalação existente permanece intacta; veja o diagnóstico acima.'; exit 1;
}
installer_validate_bundle "$installer_stage/PS1-2.app" local.rafael.centraldejogos

# Prepare every missing app before publishing any app. A network/hash/build
# failure leaves the existing installation untouched.
installer_duck_download=''; installer_pcsx_download=''
if [ "$installer_emulators" = yes ]; then
    if [ -z "$installer_duck" ]; then
        installer_step download-ps1 'Preparando PS1: baixar e verificar DuckStation oficial'
        installer_download_emulator duckstation "$installer_stage"
        installer_duck_download="$downloaded_app"
    else
        installer_step download-ps1 'PS1 pronto: DuckStation existente será preservado'
    fi
    if [ -z "$installer_pcsx" ]; then
        installer_step download-ps2 'Preparando PS2: baixar e verificar PCSX2 estável oficial'
        installer_download_emulator pcsx2 "$installer_stage"
        installer_pcsx_download="$downloaded_app"
    else
        installer_step download-ps2 'PS2 pronto: PCSX2 existente será preservado'
    fi
else
    installer_step download-ps1 'PS1: download não solicitado; instalar somente a central'
    installer_step download-ps2 'PS2: download não solicitado; instalar somente a central'
fi
installer_step install 'Instalando os apps verificados e preservando a central anterior'
if [ -n "$installer_duck_download" ]; then
    installer_publish_app "$installer_duck_download" "$installer_destination/DuckStation.app" com.github.stenzek.duckstation no
fi
if [ -n "$installer_pcsx_download" ]; then
    installer_publish_app "$installer_pcsx_download" "$installer_destination/PCSX2.app" net.pcsx2.pcsx2 no
fi
if [ -e "$installer_target" ]; then installer_launcher_closed; fi
installer_publish_app "$installer_stage/PS1-2.app" "$installer_target" local.rafael.centraldejogos yes
installer_refresh_dock_icon "$installer_target" local.rafael.centraldejogos
printf '\nInstalação concluída. Não é preciso reiniciar o Mac.\n'
printf 'A central foi registrada no macOS; nenhum cache global foi apagado e o Dock não foi reiniciado.\n'
printf 'Próximos passos:\n1. Abra DuckStation/PCSX2 e configure sua BIOS e seu controle.\n2. Teste um jogo diretamente no emulador.\n3. Abra a central:\n'
printf 'open "%s"\n' "$installer_target"
printf '4. Em Pastas de jogos (⌘,), escolha suas bibliotecas no Mac ou em um disco externo.\n'
printf 'O padrão permanece /Volumes/Extreme SSD/Emulacao/{PS1,PS2}/Jogos. X/Enter entra na biblioteca e confirma o jogo; T/△ atualiza dentro dela.\n'
printf 'BIOS e jogos são fornecidos por você. Leia README.md e docs/EMULADORES.md para o primeiro uso.\n'
installer_step complete 'Tudo instalado. Configure seus emuladores, escolha os jogos e aproveite'
