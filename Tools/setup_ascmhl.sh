#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VENV_DIR="${ASCMHL_VENV:-$ROOT_DIR/build/ascmhl-venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check "ascmhl==1.2"

echo "ascmhl 1.2 installed at $VENV_DIR/bin/ascmhl"
