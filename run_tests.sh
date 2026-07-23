#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
MODULE_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/321doit-test-modcache.XXXXXX")"
XXH_OBJECT="$MODULE_CACHE/XXHash64Fast-$ARCH-test.o"
trap 'rm -rf "$MODULE_CACHE"' EXIT

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

# English mode must never fall through to a hard-coded Chinese control or
# AppKit alert. All visible UI copy should pass through L10n.t instead.
ENGLISH_CLEAN_UI_PATTERN='(Text|Label|Button|Picker|TextField|SecureField|Toggle|Menu)\("[^"\n]*[一-龥]|\.help\("[^"\n]*[一-龥]|\.(messageText|informativeText|title) = "[^"\n]*[一-龥]'
if rg -n --glob '*.swift' "$ENGLISH_CLEAN_UI_PATTERN" "$ROOT_DIR/Sources/321Doit"; then
  echo "English-clean check failed: localize the visible UI string above with L10n.t." >&2
  exit 1
fi

clang \
  -O3 \
  -target "$TARGET" \
  -c "$ROOT_DIR/Sources/321Doit/XXHash64Fast.c" \
  -o "$XXH_OBJECT"

SWIFTC_ARGS=(
  -O
  -D DEBUG
  -target "$TARGET"
  -module-cache-path "$MODULE_CACHE"
  -import-objc-header "$ROOT_DIR/Sources/321Doit/XXHash64Fast.h"
)

swiftc "${SWIFTC_ARGS[@]}" \
  "$ROOT_DIR/Sources/321Doit/AppLogger.swift" \
  "$ROOT_DIR/Sources/321Doit/Localization.swift" \
  "$ROOT_DIR/Sources/321Doit/CameraCardDetector.swift" \
  "$ROOT_DIR/Sources/321Doit/HandoffSettings.swift" \
  "$ROOT_DIR/Sources/321Doit/ProjectModels.swift" \
  "$ROOT_DIR/Sources/321Doit/ProjectRepository.swift" \
  "$ROOT_DIR/Sources/321Doit/ScriptLogModels.swift" \
  "$ROOT_DIR/Sources/321Doit/ScriptLogExporter.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardProductionModels.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardModels.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardCommandBus.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardAnalysisAndExport.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardPatch.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardRepository.swift" \
  "$ROOT_DIR/Sources/321Doit/StoryboardRichTextInputState.swift" \
  "$ROOT_DIR/Sources/321Doit/ChecksumTypes.swift" \
  "$ROOT_DIR/Sources/321Doit/Models.swift" \
  "$ROOT_DIR/Sources/321Doit/FFmpegLocator.swift" \
  "$ROOT_DIR/Sources/321Doit/XXHash64.swift" \
  "$ROOT_DIR/Sources/321Doit/Checksum.swift" \
  "$ROOT_DIR/Sources/321Doit/C4Hash.swift" \
  "$ROOT_DIR/Sources/321Doit/OutputFileNamer.swift" \
  "$ROOT_DIR/Sources/321Doit/AscMHLv2Writer.swift" \
  "$ROOT_DIR/Sources/321Doit/SparkleEdSignature.swift" \
  "$ROOT_DIR/Sources/321Doit/UpdateChecker.swift" \
  "$ROOT_DIR/Sources/321Doit/ProxyTranscoder.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaConvertModels.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaProbeService.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaCompatibilityService.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaProcessRunner.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaConversionEngine.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaVerificationService.swift" \
  "$ROOT_DIR/Sources/321Doit/MediaConversionReportWriter.swift" \
  "$ROOT_DIR/Sources/321Doit/Reports.swift" \
  "$ROOT_DIR/Sources/321Doit/HandoffManifest.swift" \
  "$ROOT_DIR/Sources/321Doit/HandoffResolve.swift" \
  "$ROOT_DIR/Sources/321Doit/HandoffFCPXML.swift" \
  "$ROOT_DIR/Sources/321Doit/HandoffPackageBuilder.swift" \
  "$ROOT_DIR/Sources/321Doit/OffloadEngine.swift" \
  "$ROOT_DIR/Tests/EngineSmokeTests.swift" \
  "$XXH_OBJECT" \
  -o "$BUILD_DIR/EngineSmokeTests" \
  -framework AVFoundation \
  -framework AppKit \
  -framework CoreGraphics \
  -framework IOKit

"$BUILD_DIR/EngineSmokeTests"

MCP_SOURCES=(
  "$ROOT_DIR/Sources/321Doit/AppLogger.swift"
  "$ROOT_DIR/Sources/321Doit/Localization.swift"
  "$ROOT_DIR/Sources/321Doit/CameraCardDetector.swift"
  "$ROOT_DIR/Sources/321Doit/HandoffSettings.swift"
  "$ROOT_DIR/Sources/321Doit/ProjectModels.swift"
  "$ROOT_DIR/Sources/321Doit/ProjectRepository.swift"
  "$ROOT_DIR/Sources/321Doit/ScriptLogModels.swift"
  "$ROOT_DIR/Sources/321Doit/ScriptLogExporter.swift"
  "$ROOT_DIR/Sources/321Doit/StoryboardProductionModels.swift"
  "$ROOT_DIR/Sources/321Doit/StoryboardModels.swift"
  "$ROOT_DIR/Sources/321Doit/StoryboardCommandBus.swift"
  "$ROOT_DIR/Sources/321Doit/StoryboardAnalysisAndExport.swift"
  "$ROOT_DIR/Sources/321Doit/StoryboardPatch.swift"
  "$ROOT_DIR/Sources/321Doit/StoryboardRepository.swift"
  "$ROOT_DIR/Sources/321Doit/ChecksumTypes.swift"
  "$ROOT_DIR/Sources/321Doit/Models.swift"
  "$ROOT_DIR/Sources/321Doit/MediaConvertModels.swift"
  "$ROOT_DIR/Sources/321Doit/FFmpegLocator.swift"
  "$ROOT_DIR/Sources/321Doit/XXHash64.swift"
  "$ROOT_DIR/Sources/321Doit/Checksum.swift"
  "$ROOT_DIR/Sources/321Doit/C4Hash.swift"
  "$ROOT_DIR/Sources/321Doit/OutputFileNamer.swift"
  "$ROOT_DIR/Sources/321Doit/AscMHLv2Writer.swift"
  "$ROOT_DIR/Sources/321Doit/SparkleEdSignature.swift"
  "$ROOT_DIR/Sources/321Doit/UpdateChecker.swift"
  "$ROOT_DIR/Sources/321Doit/ProxyTranscoder.swift"
  "$ROOT_DIR/Sources/321Doit/MediaProbeService.swift"
  "$ROOT_DIR/Sources/321Doit/MediaCompatibilityService.swift"
  "$ROOT_DIR/Sources/321Doit/MediaProcessRunner.swift"
  "$ROOT_DIR/Sources/321Doit/MediaConversionEngine.swift"
  "$ROOT_DIR/Sources/321Doit/MediaVerificationService.swift"
  "$ROOT_DIR/Sources/321Doit/MediaConversionReportWriter.swift"
  "$ROOT_DIR/Sources/321Doit/Reports.swift"
  "$ROOT_DIR/Sources/321Doit/HandoffManifest.swift"
  "$ROOT_DIR/Sources/321Doit/HandoffResolve.swift"
  "$ROOT_DIR/Sources/321Doit/HandoffFCPXML.swift"
  "$ROOT_DIR/Sources/321Doit/HandoffPackageBuilder.swift"
  "$ROOT_DIR/Sources/321Doit/OffloadEngine.swift"
  "$ROOT_DIR/Tools/MCP/MCPProtocol.swift"
  "$ROOT_DIR/Tools/MCP/MCPExecutionCoordinator.swift"
  "$ROOT_DIR/Tools/MCP/DoitMCPServer.swift"
)

swiftc "${SWIFTC_ARGS[@]}" \
  "${MCP_SOURCES[@]}" \
  "$ROOT_DIR/Tests/MCPSmokeTests.swift" \
  "$XXH_OBJECT" \
  -o "$BUILD_DIR/MCPSmokeTests" \
  -framework AVFoundation \
  -framework AppKit \
  -framework CoreGraphics \
  -framework IOKit

"$BUILD_DIR/MCPSmokeTests"

swiftc "${SWIFTC_ARGS[@]}" \
  "$ROOT_DIR/Sources/321Doit/AppLogger.swift" \
  "$ROOT_DIR/Sources/321Doit/SecurityScopedBookmarks.swift" \
  "$ROOT_DIR/Sources/321Doit/MiraOpenCodeBridge.swift" \
  "$ROOT_DIR/Tests/MiraTestSupport.swift" \
  "$ROOT_DIR/Tests/MiraSmokeTests.swift" \
  -o "$BUILD_DIR/MiraSmokeTests" \
  -framework AppKit

"$BUILD_DIR/MiraSmokeTests"

swiftc "${SWIFTC_ARGS[@]}" \
  "${MCP_SOURCES[@]}" \
  "$ROOT_DIR/Tools/MCP/main.swift" \
  "$XXH_OBJECT" \
  -o "$BUILD_DIR/321DoitMCP" \
  -framework AVFoundation \
  -framework AppKit \
  -framework CoreGraphics \
  -framework IOKit

MCP_PROTOCOL_OUTPUT="$(
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"321doit-tests","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    | "$BUILD_DIR/321DoitMCP" --allow-root "$ROOT_DIR"
)"
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"protocolVersion":"2025-11-25"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"storyboard_apply_patch"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"offload_preflight"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"offload_start"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"media_conversion_preflight"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"media_conversion_start"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"production_plan_upsert_call_sheet"'
print -r -- "$MCP_PROTOCOL_OUTPUT" | rg -q '"name":"script_log_record_take"'
echo "321Doit MCP stdio protocol tests passed"
