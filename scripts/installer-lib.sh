#!/bin/bash
# Shared by install.sh and offline fixture tests. Sourcing has no side effects.

installer_error() { printf 'ERRO: %s\n' "$*" >&2; return 1; }
installer_plist() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# Stable line protocol consumed by the native setup wizard. Human-readable
# output stays useful when the same installer is run directly in Terminal.
installer_step() {
    local key="$1" message="$2" number
    case "$key" in
        preflight) number=1 ;; build) number=2 ;; download-ps1) number=3 ;;
        download-ps2) number=4 ;; install) number=5 ;; complete) number=6 ;;
        *) installer_error 'Etapa de instalação desconhecida.'; return 1 ;;
    esac
    message="${message//$'\r'/ }"
    message="${message//$'\n'/ }"
    printf 'PS12_STEP:%s:%s\n' "$key" "$message"
    printf '[%s/6] %s\n' "$number" "$message"
}

installer_developer_path() { /usr/bin/xcode-select -p 2>/dev/null; }
installer_swift_path() { /usr/bin/xcrun --no-cache --find swiftc 2>/dev/null; }
installer_sdk_path() { /usr/bin/xcrun --no-cache --sdk macosx --show-sdk-path 2>/dev/null; }

installer_check_tools() {
    local developer compiler sdk
    # xcrun can invoke the system's tool-install prompt when no developer tools
    # are selected. Check selection first, and bypass its lookup cache so
    # --check remains a diagnosis, not a setup operation.
    developer="$(installer_developer_path)" && [ -d "$developer" ] || {
        installer_error 'Faltam as ferramentas de desenvolvimento da Apple. Execute xcode-select --install, conclua a instalação da Apple e abra este instalador novamente. Nada será instalado automaticamente.'
        return 1
    }
    compiler="$(installer_swift_path)" && [ -x "$compiler" ] || {
        installer_error "Swift não está disponível nas ferramentas selecionadas ($developer). Conclua ou repare as Command Line Tools/Xcode e tente novamente. Este instalador não aceita licenças por você."
        return 1
    }
    sdk="$(installer_sdk_path)" &&
        [ -d "$sdk/System/Library/Frameworks/AppKit.framework" ] || {
        installer_error 'O SDK do macOS não foi encontrado. Conclua ou repare a instalação das Command Line Tools/Xcode; depois execute novamente este instalador.'
        return 1
    }
    printf 'Ferramentas Apple e SDK do macOS encontrados.\n'
}

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
        *) installer_error 'Emulador não reconhecido.'; return 1 ;;
    esac
}

# All values come from one captured response, preventing mixed release metadata.
# No eval, shell code from the network, unauthenticated checksum fallback or tokens.
installer_select_asset() {
    local key="$1" metadata="$2" index=0 name expected found=0 digest
    installer_release_config "$key" || return 1
    [ "$(installer_plist "$metadata" draft)" = false ] &&
        [ "$(installer_plist "$metadata" prerelease)" = false ] || {
        installer_error 'A API oficial não retornou uma versão estável pública. Download cancelado.'; return 1;
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
            [ "$found" -eq 0 ] || { installer_error 'A resposta da API contém pacotes macOS duplicados.'; return 1; }
            release_url="$(installer_plist "$metadata" "assets.$index.browser_download_url")" || return 1
            [ "$release_url" = "https://github.com/$release_repository/releases/download/$release_tag/$expected" ] || {
                installer_error 'O endereço do pacote não corresponde ao repositório oficial.'; return 1;
            }
            digest="$(installer_plist "$metadata" "assets.$index.digest")" || return 1
            [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || {
                installer_error 'SHA-256 ausente ou inválido; download automático interrompido.'; return 1;
            }
            release_sha256="${digest#sha256:}"
            release_filename="$expected"
            found=1
        fi
        index=$((index + 1))
    done
    [ "$found" -eq 1 ] || { installer_error 'O pacote macOS esperado não foi encontrado. Confira a versão oficial; nenhuma alternativa não verificada será usada.'; return 1; }
}

installer_verify_sha256() {
    local actual
    [[ "$2" =~ ^[a-f0-9]{64}$ ]] || return 1
    actual="$(/usr/bin/shasum -a 256 "$1")" || return 1
    [ "${actual%% *}" = "$2" ] || { installer_error 'SHA-256 diferente do valor oficial. Nada deste pacote será instalado.'; return 1; }
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
    local app="$1" expected="$2" minimum executable architectures
    installer_bundle_identity "$app" "$expected" || { installer_error "App inesperado ou incompleto: $app"; return 1; }
    /usr/bin/codesign --verify --strict "$app" || return 1
    executable="$(installer_plist "$app/Contents/Info.plist" CFBundleExecutable)" || return 1
    architectures="$(/usr/bin/lipo -archs "$app/Contents/MacOS/$executable" 2>/dev/null)" || {
        installer_error 'Não foi possível verificar a arquitetura do executável.'; return 1;
    }
    case " $architectures " in
        *' arm64 '*|*' x86_64 '*) ;;
        *) installer_error "Arquitetura não suportada neste Mac: $architectures"; return 1 ;;
    esac
    minimum="$(installer_plist "$app/Contents/Info.plist" LSMinimumSystemVersion)" || minimum=''
    if [ -n "$minimum" ]; then
        installer_version_at_least "$(/usr/bin/sw_vers -productVersion)" "$minimum" || {
            installer_error "Este pacote exige macOS $minimum ou mais recente."; return 1;
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
    local key="$1" stage="$2" metadata archive extracted listing candidate count=0 stamp executable architectures
    installer_release_config "$key" || return 1
    metadata="$stage/$key-release.json"
    printf 'Consultando a versão oficial: %s\n' "$release_endpoint"
    /usr/bin/curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 60 --retry 2 --max-filesize 2097152 \
        --output "$metadata" "$release_endpoint" || {
        installer_error 'Não foi possível consultar a versão oficial. Confira a conexão e tente novamente; a instalação existente permanece intacta.'; return 1;
    }
    installer_select_asset "$key" "$metadata" || return 1
    archive="$stage/$release_filename"
    printf 'Baixando %s (%s)\n%s\n' "$release_app_name" "$release_tag" "$release_url"
    /usr/bin/curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 900 --retry 2 --max-filesize 314572800 \
        --output "$archive" "$release_url" || {
        installer_error 'O download não terminou. Confira a conexão e o espaço livre; nenhum pacote parcial será instalado.'; return 1;
    }
    installer_verify_sha256 "$archive" "$release_sha256" || return 1
    listing="$stage/$key-archive.txt"
    /usr/bin/tar -tf "$archive" > "$listing" || return 1
    installer_archive_paths_safe "$listing" || { installer_error 'Caminho inválido dentro do pacote baixado.'; return 1; }
    extracted="$stage/$key-extracted"
    /bin/mkdir "$extracted" || return 1
    /usr/bin/tar -xf "$archive" -C "$extracted" || return 1
    downloaded_app=''
    while IFS= read -r candidate; do
        downloaded_app="$candidate"
        count=$((count + 1))
    done < <(/usr/bin/find "$extracted" -type d -name '*.app' -prune -print)
    [ "$count" -eq 1 ] || { installer_error 'O pacote não contém exatamente um app.'; return 1; }
    installer_validate_bundle "$downloaded_app" "$release_bundle_id" || return 1
    executable="$(installer_plist "$downloaded_app/Contents/Info.plist" CFBundleExecutable)" || return 1
    architectures="$(/usr/bin/lipo -archs "$downloaded_app/Contents/MacOS/$executable" 2>/dev/null)" || return 1
    printf 'Arquitetura verificada no executável: %s\n' "$architectures"
    case " $architectures " in
        *' arm64 '*) ;;
        *) printf 'Este emulador usa Intel x86_64. Ao abri-lo, o macOS pode pedir Rosetta; a decisão e a licença são suas.\n' ;;
    esac
    # curl is not a browser: explicitly preserve normal Gatekeeper assessment
    # for these downloaded apps. Never clear quarantine or re-sign upstream apps.
    stamp="$(printf '%x' "$(/bin/date +%s)")"
    /usr/bin/xattr -w com.apple.quarantine "0083;$stamp;PS12Installer;" "$downloaded_app" || return 1
    printf 'SHA-256, assinatura e identidade verificados: %s. Quarentena do macOS mantida.\n' "$release_app_name"
}

installer_find_existing() {
    local name="$1" identity="$2" destination="$3" directory candidate
    existing_app=''
    for directory in "$destination" /Applications "$HOME/Applications"; do
        candidate="$directory/$name"
        if [ -e "$candidate" ] || [ -L "$candidate" ]; then
            installer_bundle_identity "$candidate" "$identity" || {
                installer_error "Já existe um app inesperado ou incompleto em $candidate. Confira-o manualmente; nada será sobrescrito."; return 1;
            }
            existing_app="$candidate"
            return 0
        fi
    done
}

installer_launcher_closed() {
    local output status
    if output="$(/usr/bin/pgrep -x PS12 2>&1)"; then
        installer_error 'Feche apenas a central PS1/2 (⌘Q) e tente novamente. Nenhum app será encerrado à força.'
        return 1
    else status=$?; fi
    [ "$status" -eq 1 ] && [ -z "$output" ] || {
        installer_error 'Não foi possível verificar se a central está aberta. Instalação interrompida por segurança.'; return 1;
    }
}

installer_move_exclusive() {
    [ -n "${installer_move_tool:-}" ] && [ -x "$installer_move_tool" ] || {
        installer_error 'A ferramenta de instalação segura não foi compilada.'; return 1;
    }
    "$installer_move_tool" "$1" "$2"
}

installer_rollback() {
    if [ -n "${installer_pending_backup:-}" ] && [ -e "$installer_pending_backup" ]; then
        if [ ! -e "$installer_pending_destination" ] && [ ! -L "$installer_pending_destination" ]; then
            if installer_move_exclusive "$installer_pending_backup" "$installer_pending_destination"; then
                printf 'Versão anterior restaurada: %s\n' "$installer_pending_destination" >&2
            else installer_error "Restaure manualmente o backup: $installer_pending_backup"; return 1; fi
        else
            printf 'Backup preservado: %s\n' "$installer_pending_backup" >&2
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
            printf 'Preservado, já instalado: %s\n' "$destination"
            return 0
        fi
    fi
    staging="$(/usr/bin/mktemp -d "$container/.ps12-stage.XXXXXX")" || return 1
    # Copy beside the final destination so publishing is a same-volume rename.
    /usr/bin/ditto "$source" "$staging/$name" || { installer_error "Cópia incompleta preservada em $staging"; return 1; }
    installer_validate_bundle "$staging/$name" "$identity" || return 1
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        installer_bundle_identity "$destination" "$identity" || return 1
        [ "$replace" = yes ] || { installer_error 'O destino apareceu durante a instalação; nada foi sobrescrito.'; return 1; }
        backup="$(/usr/bin/mktemp -d "$container/.ps12-backup.XXXXXX")" || return 1
        # Set recovery state before moving the old app, including for SIGINT.
        installer_pending_destination="$destination"
        installer_pending_backup="$backup/$name"
        installer_move_exclusive "$destination" "$backup/$name" || return 1
        printf 'Backup da central anterior: %s\n' "$backup/$name"
    fi
    if ! installer_move_exclusive "$staging/$name" "$destination"; then
        installer_rollback || true
        installer_error "A instalação falhou. Cópia preparada: $staging"; return 1
    fi
    installer_pending_backup=''; installer_pending_destination=''
    /bin/rmdir "$staging" || true
    printf 'Instalado: %s\n' "$destination"
}

installer_refresh_dock_icon() {
    local app="$1" identity="$2" lsregister parent
    lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    installer_bundle_identity "$app" "$identity" || return 1
    parent="$(/usr/bin/dirname "$app")"
    app="$(cd "$parent" && /bin/pwd -P)/$(/usr/bin/basename "$app")"
    # Register only this verified installation. Never unregister other copies,
    # erase shared icon caches, or restart Dock/IconServices for a cosmetic fix.
    if [ "${installer_dock_icon_dry_run:-no}" = yes ]; then
        printf 'register %s\n' "$app"
        return 0
    fi
    [ -x "$lsregister" ] && "$lsregister" -f "$app" >/dev/null 2>&1 || true
}
