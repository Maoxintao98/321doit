#!/bin/zsh
# Builds a Universal Binary (arm64 + x86_64) macOS .app for 321Doit, generates the
# app icon, ad-hoc signs the bundle so it can be moved/copied to other Macs.
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/321Doit.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/321Doit"
MCP_EXECUTABLE="$APP_DIR/Contents/Helpers/321DoitMCP"
RESOURCES="$APP_DIR/Contents/Resources"
HOST_ARCH="$(uname -m)"

APP_VERSION="0.7"
APP_BUILD_BASE="1"
DEPLOY_TARGET="13.0"

"$ROOT_DIR/Tools/check_internal_version.sh" --source

# Every ordinary/internal build receives a strictly higher integer Build.
# The last successful value lives under ignored build output, and we also
# consider an existing built app and the installed app so deleting the counter
# alone cannot accidentally move the Build backwards. A formal reproducible
# build can be pinned explicitly with APP_BUILD_OVERRIDE=<positive integer>.
mkdir -p "$BUILD_DIR"
BUILD_NUMBER_STATE="$BUILD_DIR/.internal-build-number"
BUILD_NUMBER_LOCK="$BUILD_DIR/.internal-build-number.lock"
if ! mkdir "$BUILD_NUMBER_LOCK" 2>/dev/null; then
  echo "error: another 321Doit build is already resolving an internal Build number" >&2
  echo "if no build is running, remove stale lock: $BUILD_NUMBER_LOCK" >&2
  exit 1
fi
cleanup_build_number_lock() {
  rmdir "$BUILD_NUMBER_LOCK" 2>/dev/null || true
}
trap cleanup_build_number_lock EXIT INT TERM HUP

if [[ -n "${APP_BUILD_OVERRIDE:-}" ]]; then
  [[ "$APP_BUILD_OVERRIDE" =~ '^[1-9][0-9]*$' ]] || {
    echo "error: APP_BUILD_OVERRIDE must be a positive integer" >&2
    exit 1
  }
  APP_BUILD="$APP_BUILD_OVERRIDE"
  BUILD_NUMBER_MODE="locked"
else
  HIGHEST_BUILD="$APP_BUILD_BASE"

  consider_build_number() {
    local candidate_version="$1"
    local candidate_build="$2"
    if [[ "$candidate_version" == "$APP_VERSION" && "$candidate_build" =~ '^[1-9][0-9]*$' ]] \
      && (( candidate_build > HIGHEST_BUILD )); then
      HIGHEST_BUILD="$candidate_build"
    fi
  }

  consider_app_build() {
    local candidate_app="$1"
    local candidate_plist="$candidate_app/Contents/Info.plist"
    [[ -f "$candidate_plist" ]] || return 0
    local candidate_version
    local candidate_build
    candidate_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate_plist" 2>/dev/null || true)"
    candidate_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate_plist" 2>/dev/null || true)"
    consider_build_number "$candidate_version" "$candidate_build"
  }

  if [[ -f "$BUILD_NUMBER_STATE" ]]; then
    STATE_VERSION="$(awk 'NR == 1 { print $1 }' "$BUILD_NUMBER_STATE")"
    STATE_BUILD="$(awk 'NR == 1 { print $2 }' "$BUILD_NUMBER_STATE")"
    consider_build_number "$STATE_VERSION" "$STATE_BUILD"
  fi
  consider_app_build "$APP_DIR"
  consider_app_build "${INSTALL_APP_DIR:-/Applications}/321Doit.app"

  APP_BUILD="$((HIGHEST_BUILD + 1))"
  BUILD_NUMBER_MODE="automatic"
fi
echo "  · resolved $APP_VERSION build $APP_BUILD ($BUILD_NUMBER_MODE)"

# --- SDK selection ----------------------------------------------------------
CLT_SDK_DIR="/Library/Developer/CommandLineTools/SDKs"
if [[ -n "${SDKROOT:-}" ]]; then
  SDK="$SDKROOT"
elif swiftc --version 2>/dev/null | grep -q "Apple Swift version 6.1" && [[ -d "$CLT_SDK_DIR/MacOSX15.4.sdk" ]]; then
  # Swift 6.1 matches the 15.4 SDK. Newer standalone command-line tools ship
  # a newer compiler and must use their current MacOSX.sdk symlink instead.
  SDK="$CLT_SDK_DIR/MacOSX15.4.sdk"
else
  SDK="$CLT_SDK_DIR/MacOSX.sdk"
fi
if [[ "$SDK" == *"MacOSX15.4.sdk" ]]; then
  APP_SOURCE_DEFINES=(-D LEGACY_SDK)
else
  APP_SOURCE_DEFINES=()
fi

COMPILER_SWIFT_VERSION="$(swiftc --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)"
SDK_SWIFT_INTERFACE="$SDK/System/Library/Frameworks/AppKit.framework/Modules/AppKit.swiftmodule/x86_64-apple-macos.swiftinterface"
SDK_SWIFT_VERSION="$(sed -n 's#// swift-compiler-version: Apple Swift version \([0-9][0-9.]*\).*#\1#p' "$SDK_SWIFT_INTERFACE" 2>/dev/null | head -1)"
SDK_INTERFACE_COMPILER_VERSION="$(sed -n 's#.*swiftlang-\([0-9][0-9.]*\) clang-.*#\1#p' "$SDK_SWIFT_INTERFACE" 2>/dev/null | head -1)"
if [[ -n "$COMPILER_SWIFT_VERSION" && -n "$SDK_SWIFT_VERSION" && "$COMPILER_SWIFT_VERSION" != "$SDK_SWIFT_VERSION" ]]; then
  # During a standalone CLT update the compiler can arrive before its matching
  # SDK. Compile SDK interfaces using the version recorded by that SDK; this is
  # supported by swiftc and keeps both arm64 and x86_64 slices buildable.
  SWIFT_SDK_ARGS=(-sdk "$SDK" -interface-compiler-version "$SDK_INTERFACE_COMPILER_VERSION")
  CLANG_SDK_ARGS=(-isysroot "$SDK")
else
  SWIFT_SDK_ARGS=(-sdk "$SDK")
  CLANG_SDK_ARGS=(-isysroot "$SDK")
fi

# Sparkle / appcast configuration. SUFeedURL points at the signed
# appcast.xml hosted by the project; SUPublicEDKey is the base64-encoded
# Ed25519 verification key that must match the private key used by
# Tools/SparkleSign to sign each release. Override either via env to
# point a private build at a staging feed.
APPCAST_URL_DEFAULT="https://maoxintao98.github.io/321doit/appcast.xml"
APPCAST_URL="${SUFeedURL_OVERRIDE:-$APPCAST_URL_DEFAULT}"
SPARKLE_PUB_KEY="${SUPublicEDKey:-}"
if [[ -z "$SPARKLE_PUB_KEY" && -f "$ROOT_DIR/dist/sparkle-public.key" ]]; then
  SPARKLE_PUB_KEY="$(tr -d '\n' < "$ROOT_DIR/dist/sparkle-public.key")"
fi

rm -rf "$APP_DIR" "$BUILD_DIR"/AppModuleCache-*(N) "$BUILD_DIR"/MCPModuleCache-*(N)
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$RESOURCES"

build_slice() {
  local arch="$1"
  local out="$2"
  local xxh_obj="$BUILD_DIR/XXHash64Fast-$arch.o"
  local module_cache="$BUILD_DIR/AppModuleCache-$arch"
  echo "  · compiling $arch slice"
  rm -rf "$module_cache"
  mkdir -p "$module_cache"
  clang \
    -O3 \
    "${CLANG_SDK_ARGS[@]}" \
    -target "${arch}-apple-macos${DEPLOY_TARGET}" \
    -c "$ROOT_DIR/Sources/321Doit/XXHash64Fast.c" \
    -o "$xxh_obj"
  swiftc \
    -O \
    -j 1 \
    "${SWIFT_SDK_ARGS[@]}" \
    -target "${arch}-apple-macos${DEPLOY_TARGET}" \
    -module-cache-path "$module_cache" \
    "${APP_SOURCE_DEFINES[@]}" \
    -import-objc-header "$ROOT_DIR/Sources/321Doit/XXHash64Fast.h" \
    "$ROOT_DIR"/Sources/321Doit/*.swift \
    "$xxh_obj" \
    -o "$out" \
    -framework AVFoundation \
    -framework AppKit \
    -framework CoreLocation \
    -framework SwiftUI \
    -framework CoreGraphics \
    -framework IOKit \
    -framework Security
}

MCP_SHARED_SOURCES=(
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

build_mcp_slice() {
  local arch="$1"
  local out="$2"
  local module_cache="$BUILD_DIR/MCPModuleCache-$arch"
  local xxh_obj="$BUILD_DIR/MCPXXHash64Fast-$arch.o"
  echo "  · compiling 321Doit MCP $arch slice"
  rm -rf "$module_cache"
  mkdir -p "$module_cache"
  clang \
    -O3 \
    "${CLANG_SDK_ARGS[@]}" \
    -target "${arch}-apple-macos${DEPLOY_TARGET}" \
    -c "$ROOT_DIR/Sources/321Doit/XXHash64Fast.c" \
    -o "$xxh_obj"
  swiftc \
    -O \
    -j 1 \
    "${SWIFT_SDK_ARGS[@]}" \
    -target "${arch}-apple-macos${DEPLOY_TARGET}" \
    -module-cache-path "$module_cache" \
    -import-objc-header "$ROOT_DIR/Sources/321Doit/XXHash64Fast.h" \
    "${MCP_SHARED_SOURCES[@]}" \
    "$ROOT_DIR/Tools/MCP/main.swift" \
    "$xxh_obj" \
    -o "$out" \
    -framework AVFoundation \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit
}

ARM_SLICE="$BUILD_DIR/321Doit-arm64"
INTEL_SLICE="$BUILD_DIR/321Doit-x86_64"
MCP_ARM_SLICE="$BUILD_DIR/321DoitMCP-arm64"
MCP_INTEL_SLICE="$BUILD_DIR/321DoitMCP-x86_64"

CAN_BUILD_INTEL=1
if [[ "$HOST_ARCH" == "arm64" && -n "$COMPILER_SWIFT_VERSION" && -n "$SDK_SWIFT_VERSION" && "$COMPILER_SWIFT_VERSION" != "$SDK_SWIFT_VERSION" && -z "$SDK_INTERFACE_COMPILER_VERSION" ]]; then
  # Last-resort fallback for an incomplete SDK that does not publish a usable
  # interface compiler version.
  CAN_BUILD_INTEL=0
fi

if [[ "$CAN_BUILD_INTEL" == "1" ]]; then
  echo "Building Universal Binary (arm64 + x86_64)…"
else
  echo "Building native arm64 app (installed Swift $COMPILER_SWIFT_VERSION and SDK Swift $SDK_SWIFT_VERSION cannot cross-build x86_64)…"
fi
if [[ "${USE_EXISTING_SLICES:-0}" == "1" ]]; then
  if [[ ! -x "$ARM_SLICE" || ! -x "$INTEL_SLICE" ]]; then
    echo "error: USE_EXISTING_SLICES=1 requires both architecture slices" >&2
    exit 1
  fi
  echo "  · using verified arm64 and x86_64 slices"
else
  build_slice "arm64" "$ARM_SLICE"
  if [[ "$CAN_BUILD_INTEL" == "1" ]]; then
    build_slice "x86_64" "$INTEL_SLICE"
  fi
fi

if [[ "$CAN_BUILD_INTEL" == "1" ]]; then
  echo "  · lipo → universal"
  lipo -create -output "$EXECUTABLE" "$ARM_SLICE" "$INTEL_SLICE"
else
  echo "  · native arm64 executable"
  cp "$ARM_SLICE" "$EXECUTABLE"
fi
rm -f "$ARM_SLICE" "$INTEL_SLICE"
rm -f "$BUILD_DIR"/XXHash64Fast-*.o(N)

if [[ "${USE_EXISTING_MCP_SLICES:-0}" == "1" ]]; then
  if [[ ! -x "$MCP_ARM_SLICE" || ( "$CAN_BUILD_INTEL" == "1" && ! -x "$MCP_INTEL_SLICE" ) ]]; then
    echo "error: USE_EXISTING_MCP_SLICES=1 requires all required MCP architecture slices" >&2
    exit 1
  fi
  echo "  · using verified MCP architecture slices"
else
  build_mcp_slice "arm64" "$MCP_ARM_SLICE"
  if [[ "$CAN_BUILD_INTEL" == "1" ]]; then
    build_mcp_slice "x86_64" "$MCP_INTEL_SLICE"
  fi
fi
if [[ "$CAN_BUILD_INTEL" == "1" ]]; then
  lipo -create -output "$MCP_EXECUTABLE" "$MCP_ARM_SLICE" "$MCP_INTEL_SLICE"
else
  cp "$MCP_ARM_SLICE" "$MCP_EXECUTABLE"
fi
rm -f "$MCP_ARM_SLICE" "$MCP_INTEL_SLICE"
rm -f "$BUILD_DIR"/MCPXXHash64Fast-*.o(N)
chmod 755 "$MCP_EXECUTABLE"

# --- Mira / OpenCode --------------------------------------------------------
# Mira v1 intentionally targets Apple Silicon. The rest of 321Doit can remain
# Universal 2; Intel Macs receive a clear unsupported state from the bridge.
OPENCODE_SOURCE="${OPENCODE_SOURCE:-}"
if [[ -z "$OPENCODE_SOURCE" && -x "$ROOT_DIR/Vendor/OpenCode/bin/opencode" ]]; then
  OPENCODE_SOURCE="$ROOT_DIR/Vendor/OpenCode/bin/opencode"
fi
if [[ -z "$OPENCODE_SOURCE" && "$HOST_ARCH" == "arm64" ]]; then
  for candidate in \
    "$HOME/.npm-global/bin/opencode" \
    "$HOME/.opencode/bin/opencode" \
    "/opt/homebrew/bin/opencode"; do
    if [[ -x "$candidate" ]]; then
      OPENCODE_SOURCE="$candidate"
      break
    fi
  done
fi
if [[ -n "$OPENCODE_SOURCE" ]]; then
  OPENCODE_RESOLVED="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$OPENCODE_SOURCE")"
  OPENCODE_ARCHS="$(lipo -archs "$OPENCODE_RESOLVED" 2>/dev/null || true)"
  if [[ "$OPENCODE_ARCHS" != *arm64* ]]; then
    echo "error: Mira requires an arm64 OpenCode executable: $OPENCODE_RESOLVED ($OPENCODE_ARCHS)" >&2
    exit 1
  fi
  mkdir -p "$RESOURCES/Tools" "$RESOURCES/ThirdParty/OpenCode"
  cp "$OPENCODE_RESOLVED" "$RESOURCES/Tools/opencode"
  chmod 755 "$RESOURCES/Tools/opencode"
  printf '%s\n' \
    "OpenCode embedded for Mira AI Mode" \
    "Architecture: arm64" \
    "Source: https://github.com/anomalyco/opencode" \
    > "$RESOURCES/ThirdParty/OpenCode/BUILD-INFO.txt"
  echo "  · embedded OpenCode arm64 backend for Mira"
elif [[ "${REQUIRE_BUNDLED_OPENCODE:-0}" == "1" ]]; then
  echo "error: REQUIRE_BUNDLED_OPENCODE=1 but no arm64 OpenCode executable was found" >&2
  exit 1
else
  echo "  · OpenCode payload not embedded (Mira will use a compatible local installation)"
fi

# Keep a single, user-readable acknowledgement list in every app build. It
# covers runtime components and the ascmhl reference implementation used only
# by the project's verification suite.
mkdir -p "$RESOURCES/ThirdParty"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES/ThirdParty/NOTICE.md"

# --- App icon ---------------------------------------------------------------
ICON_SOURCE="$ROOT_DIR/Sources/321Doit/Resources/AppIcon.icns"
PROJECT_ICON_SOURCE="$ROOT_DIR/Sources/321Doit/Resources/ProjectIcon.icns"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "error: required AppIcon.icns was not found: $ICON_SOURCE" >&2
  exit 1
fi
if [[ ! -f "$PROJECT_ICON_SOURCE" ]]; then
  echo "error: required ProjectIcon.icns was not found: $PROJECT_ICON_SOURCE" >&2
  exit 1
fi
cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
cp "$PROJECT_ICON_SOURCE" "$RESOURCES/ProjectIcon.icns"

# --- Info.plist -------------------------------------------------------------
if [[ "$CAN_BUILD_INTEL" == "1" ]]; then
  ARCH_PRIORITY_PLIST=$'    <string>arm64</string>\n    <string>x86_64</string>'
else
  ARCH_PRIORITY_PLIST='    <string>arm64</string>'
fi
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>321Doit</string>
  <key>CFBundleExecutable</key>
  <string>321Doit</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeIconFile</key>
      <string>ProjectIcon.icns</string>
      <key>CFBundleTypeName</key>
      <string>321Doit Project</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.321doit.project</string>
      </array>
      <key>LSTypeIsPackage</key>
      <true/>
    </dict>
  </array>
  <key>CFBundleIdentifier</key>
  <string>com.321doit.copy</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>NSLocationUsageDescription</key>
  <string>321Doit uses this Mac's approximate location to calculate sunrise and sunset for shooting days.</string>
  <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
  <string>321Doit uses this Mac's approximate location to calculate sunrise and sunset for shooting days.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>321Doit uses this Mac's approximate location to calculate sunrise and sunset for shooting days.</string>
  <key>CFBundleName</key>
  <string>321Doit</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.video</string>
  <key>LSMinimumSystemVersion</key>
  <string>${DEPLOY_TARGET}</string>
  <key>LSArchitecturePriority</key>
  <array>
${ARCH_PRIORITY_PLIST}
  </array>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 321Doit Project. Free &amp; open source.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>${APPCAST_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUB_KEY}</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>com.apple.package</string>
      </array>
      <key>UTTypeDescription</key>
      <string>321Doit Project</string>
      <key>UTTypeIdentifier</key>
      <string>com.321doit.project</string>
      <key>UTTypeIconFile</key>
      <string>ProjectIcon.icns</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>321doit</string>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [[ -d "$ROOT_DIR/Sources/321Doit/Resources" ]]; then
  cp -R "$ROOT_DIR/Sources/321Doit/Resources/." "$RESOURCES/"
fi
[[ -f "$RESOURCES/Mira/mira.md" ]] || {
  echo "error: required Mira persona resource was not packaged: $RESOURCES/Mira/mira.md" >&2
  exit 1
}
[[ -f "$RESOURCES/Mira/Mira.png" ]] || {
  echo "error: required Mira logo was not packaged: $RESOURCES/Mira/Mira.png" >&2
  exit 1
}

# Offline release dependency payload. The app prefers a native-compatible
# system FFmpeg and otherwise uses these bundled Universal 2 tools.
FFMPEG_VENDOR="$ROOT_DIR/Vendor/FFmpeg"
if [[ -x "$FFMPEG_VENDOR/bin/ffmpeg" && -x "$FFMPEG_VENDOR/bin/ffprobe" ]]; then
  mkdir -p "$RESOURCES/Tools" "$RESOURCES/ThirdParty/FFmpeg"
  cp "$FFMPEG_VENDOR/bin/ffmpeg" "$RESOURCES/Tools/ffmpeg"
  cp "$FFMPEG_VENDOR/bin/ffprobe" "$RESOURCES/Tools/ffprobe"
  chmod 755 "$RESOURCES/Tools/ffmpeg" "$RESOURCES/Tools/ffprobe"
  cp "$FFMPEG_VENDOR/COPYING.LGPLv2.1" "$RESOURCES/ThirdParty/FFmpeg/"
  cp "$FFMPEG_VENDOR/COPYING.LGPLv3" "$RESOURCES/ThirdParty/FFmpeg/"
  cp "$FFMPEG_VENDOR/BUILD-INFO.txt" "$RESOURCES/ThirdParty/FFmpeg/"

  for tool in "$RESOURCES/Tools/ffmpeg" "$RESOURCES/Tools/ffprobe"; do
    ARCHS="$(lipo -archs "$tool")"
    [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || {
      echo "error: offline dependency is not Universal 2: $tool ($ARCHS)" >&2
      exit 1
    }
  done
  echo "  · embedded offline FFmpeg/FFprobe payload"
elif [[ "${REQUIRE_BUNDLED_FFMPEG:-0}" == "1" ]]; then
  echo "error: REQUIRE_BUNDLED_FFMPEG=1 but Vendor/FFmpeg/bin is incomplete" >&2
  echo "run ./Tools/build_ffmpeg_bundle.sh once" >&2
  exit 1
else
  echo "  · offline FFmpeg payload not present (development build)"
fi

# --- Ad-hoc sign so other Macs accept the bundle ----------------------------
# NOTE: hardened runtime (--options runtime) is intentionally OFF. With an
# ad-hoc signature (no Apple Developer ID) + no notarization, enabling the
# hardened runtime caused Gatekeeper/the kernel to kill the app on launch for
# users who downloaded it (com.apple.quarantine attached) — perceived as
# "opens and immediately crashes". Without hardened runtime, a downloaded
# ad-hoc build launches after the user does right-click ▸ Open on first run.
# The forward path when a Developer ID is available: sign with "Developer ID"
# + xcrun notarytool, then re-enable --options runtime.
echo "Ad-hoc signing…"
find "$APP_DIR" -name '._*' -type f -delete 2>/dev/null || true
# Cloud-backed folders (notably OneDrive/iCloud Drive) can attach FinderInfo,
# provenance, and File Provider metadata while the bundle is assembled. Those
# attributes are not part of the app and make codesign reject the bundle.
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "  · signature valid"

EXPECTED_APP_VERSION="$APP_VERSION" EXPECTED_APP_BUILD="$APP_BUILD" \
  "$ROOT_DIR/Tools/check_internal_version.sh" --built-app "$APP_DIR"

# Commit the counter only after compilation, signing and version verification
# all succeed. A failed build therefore never consumes a Build number. A
# reproducible locked build may be older than the latest internal build, so it
# must never move the monotonic counter backwards.
STATE_BUILD_TO_SAVE="$APP_BUILD"
if [[ -f "$BUILD_NUMBER_STATE" ]]; then
  PREVIOUS_STATE_VERSION="$(awk 'NR == 1 { print $1 }' "$BUILD_NUMBER_STATE")"
  PREVIOUS_STATE_BUILD="$(awk 'NR == 1 { print $2 }' "$BUILD_NUMBER_STATE")"
  if [[ "$PREVIOUS_STATE_VERSION" == "$APP_VERSION" && "$PREVIOUS_STATE_BUILD" =~ '^[1-9][0-9]*$' ]] \
    && (( PREVIOUS_STATE_BUILD > STATE_BUILD_TO_SAVE )); then
    STATE_BUILD_TO_SAVE="$PREVIOUS_STATE_BUILD"
  fi
fi
STATE_TEMP="$BUILD_NUMBER_STATE.tmp.$$"
print -r -- "$APP_VERSION $STATE_BUILD_TO_SAVE" > "$STATE_TEMP"
mv "$STATE_TEMP" "$BUILD_NUMBER_STATE"

# Report final architectures so it's obvious in CI logs
ARCHS_FOUND="$(lipo -archs "$EXECUTABLE")"
echo "Built $APP_DIR  (arch: $ARCHS_FOUND, version $APP_VERSION build $APP_BUILD)"
