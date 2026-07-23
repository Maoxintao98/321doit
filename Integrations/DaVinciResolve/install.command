#!/bin/bash
# Install the 321Doit Resolve Workflow Integration plugin.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="com.321doit.resolve.workflow"
PLUGIN_SOURCE="$SOURCE_DIR/workflow-plugin/$PLUGIN_ID"
PLUGIN_ROOT="${DOIT_PLUGIN_ROOT:-/Library/Application Support/Blackmagic Design/DaVinci Resolve/Workflow Integration Plugins}"
PLUGIN_TARGET="$PLUGIN_ROOT/$PLUGIN_ID"
SDK_NODE="${DOIT_SDK_NODE:-/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Workflow Integrations/Examples/SamplePromisePlugin/WorkflowIntegration.node}"
STAGE="$(mktemp -d /private/tmp/321doit-workflow.XXXXXX)"

SCRIPTS_BASE="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"
SUPPORT_DIR="$HOME/Library/Application Support/321Doit/ResolveBridge"

cleanup() {
    rm -rf "$STAGE" 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -d "$PLUGIN_SOURCE" ]; then
    echo "Workflow plugin source is missing: $PLUGIN_SOURCE"
    exit 1
fi
if [ ! -f "$SDK_NODE" ]; then
    echo "Resolve WorkflowIntegration.node is missing:"
    echo "  $SDK_NODE"
    echo "Reinstall DaVinci Resolve Studio and its Developer files."
    exit 1
fi

mkdir -p "$PLUGIN_ROOT" 2>/dev/null || true

echo "Preparing 321Doit Workflow Integration..."
mkdir -p "$STAGE/$PLUGIN_ID/backend"
rsync -a --delete \
    --exclude "__pycache__" \
    --exclude ".DS_Store" \
    "$PLUGIN_SOURCE/" "$STAGE/$PLUGIN_ID/"
rsync -a --delete \
    --exclude "__pycache__" \
    --exclude ".DS_Store" \
    "$SOURCE_DIR/bridge/" "$STAGE/$PLUGIN_ID/backend/bridge/"
cp -X "$SDK_NODE" "$STAGE/$PLUGIN_ID/WorkflowIntegration.node"
chmod 755 "$STAGE/$PLUGIN_ID/backend/workflow_cli.py"

# Workflow Integration Plugins are system-wide in Resolve. The stock Resolve
# directory is root-owned, so use the standard macOS administrator prompt only
# when the current account cannot write there directly.
if [ -w "$PLUGIN_ROOT" ]; then
    rm -rf "$PLUGIN_TARGET"
    cp -R "$STAGE/$PLUGIN_ID" "$PLUGIN_TARGET"
else
    /usr/bin/osascript - "$STAGE/$PLUGIN_ID" "$PLUGIN_ROOT" "$PLUGIN_TARGET" <<'APPLESCRIPT'
on run argv
    set stagedPlugin to item 1 of argv
    set pluginRoot to item 2 of argv
    set pluginTarget to item 3 of argv
    set commandText to "/bin/mkdir -p " & quoted form of pluginRoot & " && /bin/rm -rf " & quoted form of pluginTarget & " && /bin/cp -R " & quoted form of stagedPlugin & " " & quoted form of pluginTarget & " && /usr/sbin/chown -R root:staff " & quoted form of pluginTarget & " && /bin/chmod -R a+rX " & quoted form of pluginTarget
    do shell script commandText with administrator privileges
end run
APPLESCRIPT
fi

# Remove every previous Utility Script entry. The Workflow Integration is the
# sole production entry now, so Resolve will not show two 321Doit commands.
rm -f "$SCRIPTS_BASE/321Doit Bridge.lua" "$SCRIPTS_BASE/321Doit Bridge.py" 2>/dev/null || true
rm -rf "$SCRIPTS_BASE/321Doit" 2>/dev/null || true

# Remove legacy installed code but preserve results/, which is user audit data.
rm -rf "$SUPPORT_DIR/bridge" 2>/dev/null || true
rm -f "$SUPPORT_DIR/321Doit Bridge.py" "$SUPPORT_DIR/launcher.log" \
    "$SUPPORT_DIR/README.md" "$SUPPORT_DIR/README.zh-CN.md" 2>/dev/null || true

echo
echo "Installed: $PLUGIN_TARGET"
echo "Restart DaVinci Resolve, then open:"
echo "  Workspace -> Workflow Integrations -> 321Doit"
