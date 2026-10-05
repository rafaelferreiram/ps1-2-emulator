#!/bin/bash
# Shared, read-only validation. Sourcing this file does not inspect or change files.
ps12_source_check() {
    local source="$1" manifest relative count=0 missing=0
    manifest="$source/scripts/required-files.txt"
    if [ ! -f "$manifest" ] || [ ! -r "$manifest" ]; then
        printf 'ERRO: o download está incompleto; falta scripts/required-files.txt.\nPasta reconhecida: %s\nExtraia o ZIP completo e abra Instalar.command dentro da pasta extraída.\n' "$source" >&2
        return 1
    fi
    while IFS= read -r relative || [ -n "$relative" ]; do
        case "$relative" in ''|\#*) continue ;; esac
        case "$relative" in /*|..|../*|*/../*|*/..|*$'\r'*)
            printf 'ERRO: lista de arquivos inválida. Baixe novamente o ZIP completo do repositório.\n' >&2
            return 1 ;;
        esac
        count=$((count + 1))
        if [ ! -f "$source/$relative" ] || [ ! -r "$source/$relative" ]; then
            printf 'Arquivo obrigatório ausente ou sem leitura: %s\n' "$relative" >&2
            missing=$((missing + 1))
        fi
    done < "$manifest"
    if [ "$count" -eq 0 ]; then
        printf 'ERRO: a lista de arquivos está vazia. Baixe novamente o ZIP completo do repositório.\n' >&2
        return 1
    fi
    if [ "$missing" -gt 0 ]; then
        printf 'ERRO: o download está incompleto ou sem acesso (%s arquivo(s)).\nPasta reconhecida: %s\nExtraia novamente o ZIP inteiro. Não mova apenas Instalar.command para outra pasta.\n' "$missing" "$source" >&2
        return 1
    fi
}
