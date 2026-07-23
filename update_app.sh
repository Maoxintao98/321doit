#!/bin/zsh
# Daily update command. Builds and replaces 321Doit.app directly; no DMG/PKG.
set -euo pipefail
exec "${0:A:h}/Tools/install_app.sh" "$@"
