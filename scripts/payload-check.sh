#!/bin/bash
# Read-only DMG validation. Source installer-lib.sh before calling this function.
# All executable paths come from this distribution, never from the environment.
ps12_payload_check() {
    local source="$1" relative helper architectures executable
    installer_distribution=source
    installer_arch_tool=''
    installer_move_tool=''
    [[ "$source" = /* ]] && [ -d "$source" ] && [ ! -L "$source" ] || {
        installer_error 'A pasta do instalador DMG está inválida.'; return 1;
    }
    for relative in distribution.plist install.sh scripts/installer-lib.sh scripts/payload-check.sh; do
        [ -f "$source/$relative" ] && [ -r "$source/$relative" ] && [ ! -L "$source/$relative" ] || {
            installer_error "Instalador DMG incompleto: $relative. Baixe novamente o DMG."; return 1;
        }
    done
    [ "$(installer_plist "$source/distribution.plist" PS12Distribution)" = prebuilt-v1 ] || {
        installer_error 'Formato de instalador DMG inválido. Baixe novamente o DMG.'; return 1;
    }
    for relative in scripts payload payload/PS1-2.app payload/PS1-2.app/Contents payload/PS1-2.app/Contents/MacOS; do
        [ -d "$source/$relative" ] && [ -r "$source/$relative" ] && [ ! -L "$source/$relative" ] || {
            installer_error "Instalador DMG incompleto: $relative. Baixe novamente o DMG."; return 1;
        }
    done
    for helper in InspectMachO MoveApp; do
        [ -f "$source/payload/$helper" ] && [ -r "$source/payload/$helper" ] &&
            [ -x "$source/payload/$helper" ] && [ ! -L "$source/payload/$helper" ] || {
            installer_error "Componente ausente ou inválido no DMG: payload/$helper."; return 1;
        }
        /usr/bin/codesign --verify --strict "$source/payload/$helper" || {
            installer_error "Assinatura inválida no componente $helper. Baixe novamente o DMG."; return 1;
        }
    done
    installer_distribution=prebuilt-v1
    installer_arch_tool="$source/payload/InspectMachO"
    for helper in InspectMachO MoveApp; do
        architectures="$(installer_architectures "$source/payload/$helper")" || {
            installer_error "Não foi possível verificar o componente $helper do DMG."; return 1;
        }
        case " $architectures " in *' arm64 '*) ;; *)
            installer_error "O componente $helper não é compatível com Apple Silicon."; return 1 ;;
        esac
    done
    installer_validate_bundle "$source/payload/PS1-2.app" local.rafael.centraldejogos || {
        installer_error 'A central incluída no DMG está inválida ou incompatível. Baixe novamente o DMG.'; return 1;
    }
    executable="$(installer_plist "$source/payload/PS1-2.app/Contents/Info.plist" CFBundleExecutable)" || return 1
    architectures="$(installer_architectures "$source/payload/PS1-2.app/Contents/MacOS/$executable")" || return 1
    case " $architectures " in *' arm64 '*) ;; *)
        installer_error 'A central incluída no DMG exige uma arquitetura incompatível com este Mac.'; return 1 ;;
    esac
    installer_move_tool="$source/payload/MoveApp"
    printf 'Central e componentes do DMG verificados. Não são necessárias ferramentas de desenvolvimento da Apple.\n'
}
