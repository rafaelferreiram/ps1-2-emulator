#!/bin/bash
installer_source="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$installer_source/install.sh" "$@"
installer_status=$?
printf '\nPress Enter to close this window.'
if [ -t 0 ]; then read -r; fi
exit "$installer_status"
