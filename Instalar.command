#!/bin/bash
installer_source="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$installer_source/install.sh" "$@"
installer_status=$?
printf '\nPressione Enter para fechar esta janela.'
if [ -t 0 ]; then read -r; fi
exit "$installer_status"
