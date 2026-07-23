#!/bin/zsh
# Rigorous test suite for 321Doit.
#
# This goes beyond the quick smoke tests in run_tests.sh. It exercises:
#   - Large file offload (50+ MB)
#   - Cancellation and resume
#   - Multi-target partial failure
#   - CJK / emoji / space paths
#   - Audit log generation and schema validation
#   - ASC MHL v2 cross-validation (if ascmhl is installed)
#   - PDF pagination with 10 / 100 / 1000 file counts
#
# Usage:
#   ./run_rigorous_tests.sh          # standard rigorous suite
#   ./run_rigorous_tests.sh --full   # includes PDF pagination samples
#
# Typical runtime: 30–90 seconds (standard), 2–5 minutes (--full).
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
MODULE_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/321doit-rigorous-modcache.XXXXXX")"
XXH_OBJECT="$BUILD_DIR/XXHash64Fast-$ARCH-rigorous.o"
trap 'rm -rf "$MODULE_CACHE"; rm -f "$XXH_OBJECT"' EXIT

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

echo "=== 321Doit Rigorous Test Suite ==="
echo "Architecture: $ARCH"
echo ""

# Check optional dependencies
if [[ -x "$ROOT_DIR/build/ascmhl-venv/bin/ascmhl" ]] || command -v ascmhl &>/dev/null || [[ -x "$HOME/Library/Python/3.14/bin/ascmhl" ]] || [[ -x "$HOME/Library/Python/3.13/bin/ascmhl" ]] || [[ -x "$HOME/Library/Python/3.12/bin/ascmhl" ]]; then
    echo "✓ ascmhl found — MHL cross-validation will run"
else
    echo "○ ascmhl not found — MHL cross-validation will be skipped"
    echo "  Install: ./Tools/setup_ascmhl.sh"
fi
echo ""

echo "Compiling test binary…"
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

echo "Compilation OK"
echo ""

# Run the standard test suite (includes new rigorous tests)
echo "Running rigorous tests…"
"$BUILD_DIR/EngineSmokeTests"

# Optionally run PDF pagination samples
if [[ "${1:-}" == "--full" ]]; then
    echo ""
    echo "Running PDF pagination samples (this may take a few minutes)…"
    RUN_PDF_SAMPLES=1 "$BUILD_DIR/EngineSmokeTests"
    if [[ -f "$BUILD_DIR/ReportHardeningSamples/summary.txt" ]]; then
        echo ""
        echo "PDF pagination summary:"
        cat "$BUILD_DIR/ReportHardeningSamples/summary.txt"
    fi
fi

echo ""
echo "=== All rigorous tests passed ==="
