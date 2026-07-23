#!/bin/zsh
# Compile-on-demand wrapper around Tools/SparkleSign.swift. The CLI binary
# is cached under build/SparkleSign so repeated calls during a release
# don't pay the Swift compile cost. Forwards all arguments to the binary.
set -euo pipefail

ROOT_DIR="${0:A:h}/.."
BUILD_DIR="$ROOT_DIR/build"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
BIN="$BUILD_DIR/SparkleSign"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
MODULE_CACHE="$BUILD_DIR/SparkleSignModuleCache-$ARCH"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

# Standalone Command Line Tools updates can briefly leave swiftc one patch
# ahead of the bundled SDK. build.sh already handles this; the release signer
# must use the same compatibility rule or a clean release machine can build the
# app but fail exactly when it needs to sign the appcast artifact.
COMPILER_SWIFT_VERSION="$(swiftc --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)"
if [[ "$ARCH" == "arm64" ]]; then
  SDK_INTERFACE="$SDK/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface"
else
  SDK_INTERFACE="$SDK/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/x86_64-apple-macos.swiftinterface"
fi
SDK_SWIFT_VERSION="$(sed -n 's#// swift-compiler-version: Apple Swift version \([0-9][0-9.]*\).*#\1#p' "$SDK_INTERFACE" 2>/dev/null | head -1)"
SDK_INTERFACE_COMPILER_VERSION="$(sed -n 's#.*-interface-compiler-version \([0-9][0-9.]*\).*#\1#p' "$SDK_INTERFACE" 2>/dev/null | head -1)"
SWIFT_SDK_ARGS=(-sdk "$SDK")
if [[ -n "$COMPILER_SWIFT_VERSION" && -n "$SDK_SWIFT_VERSION" && "$COMPILER_SWIFT_VERSION" != "$SDK_SWIFT_VERSION" ]]; then
  [[ -n "$SDK_INTERFACE_COMPILER_VERSION" ]] || {
    echo "error: Swift $COMPILER_SWIFT_VERSION and SDK Swift $SDK_SWIFT_VERSION differ, but the SDK has no interface compiler version" >&2
    exit 1
  }
  SWIFT_SDK_ARGS+=(-interface-compiler-version "$SDK_INTERFACE_COMPILER_VERSION")
fi

# Rebuild if any of the inputs are newer than the cached binary.
needs_build=0
if [[ ! -x "$BIN" ]]; then
  needs_build=1
else
  for src in \
    "$ROOT_DIR/Tools/SparkleSign.swift" \
    "$ROOT_DIR/Sources/321Doit/SparkleEdSignature.swift"
  do
    if [[ "$src" -nt "$BIN" ]]; then
      needs_build=1
      break
    fi
  done
fi

if (( needs_build )); then
  swiftc \
    -O \
    "${SWIFT_SDK_ARGS[@]}" \
    -target "$TARGET" \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT_DIR/Tools/SparkleSign.swift" \
    "$ROOT_DIR/Sources/321Doit/SparkleEdSignature.swift" \
    -o "$BIN"
fi

exec "$BIN" "$@"
