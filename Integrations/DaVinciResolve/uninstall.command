#!/bin/bash
# Remove 321Doit Resolve integration code while preserving audit results.

set -euo pipefail

PLUGIN_ID="com.321doit.resolve.workflow"
PLUGIN_ROOT="${DOIT_PLUGIN_ROOT:-/Library/Application Support/Blackmagic Design/DaVinci Resolve/Workflow Integration Plugins}"
PLUGIN_TARGET="$PLUGIN_ROOT/$PLUGIN_ID"
SCRIPTS_BASE="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"
SUPPORT_DIR="$HOME/Library/Application Support/321Doit/ResolveBridge"

if [ -e "$PLUGIN_TARGET" ]; then
    if [ -w "$PLUGIN_ROOT" ]; then
        rm -rf "$PLUGIN_TARGET"
    else
        /usr/bin/osascript - "$PLUGIN_TARGET" <<'APPLESCRIPT'
on run argv
    do shell script "/bin/rm -rf " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
    fi
fi

rm -f "$SCRIPTS_BASE/321Doit Bridge.lua" "$SCRIPTS_BASE/321Doit Bridge.py" 2>/dev/null || true
rm -rf "$SCRIPTS_BASE/321Doit" 2>/dev/null || true
rm -rf "$SUPPORT_DIR/bridge" 2>/dev/null || true
rm -f "$SUPPORT_DIR/321Doit Bridge.py" "$SUPPORT_DIR/launcher.log" \
    "$SUPPORT_DIR/README.md" "$SUPPORT_DIR/README.zh-CN.md" 2>/dev/null || true

if [ -d "$SUPPORT_DIR/results" ]; then
    echo "Preserved user audit data: $SUPPORT_DIR/results"
fi
echo "321Doit Workflow Integration removed."
