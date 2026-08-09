#!/bin/zsh
# Download the pinned official OpenCode macOS command-line assets and combine
# them into the Universal 2 backend shipped with 321Doit.
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="${OPENCODE_VERSION:-1.18.15}"
ARM64_SHA256="${OPENCODE_ARM64_SHA256:-bd60b57cb9fe0494a5352c807424d36d6d7853cf6dbddb97065c7ccd3c5d391c}"
X86_64_SHA256="${OPENCODE_X86_64_SHA256:-234e67a90a16a8fa670131b097dfb72aabc4a2cc863a7be459be0215deb18a3f}"
RELEASE_BASE="https://github.com/anomalyco/opencode/releases/download/v${VERSION}"
SOURCE_DIR="$ROOT_DIR/Vendor/OpenCode/source"
OUTPUT_DIR="$ROOT_DIR/Vendor/OpenCode"
WORK_DIR="$ROOT_DIR/build/opencode-${VERSION}"
ARM64_ARCHIVE="$SOURCE_DIR/opencode-${VERSION}-darwin-arm64.zip"
X86_64_ARCHIVE="$SOURCE_DIR/opencode-${VERSION}-darwin-x64-baseline.zip"

if [[ "$VERSION" != "1.18.15" ]] \
   && [[ -z "${OPENCODE_ARM64_SHA256:-}" || -z "${OPENCODE_X86_64_SHA256:-}" ]]; then
  echo "error: a non-default OpenCode version requires both official archive SHA-256 values" >&2
  exit 1
fi

mkdir -p "$SOURCE_DIR" "$OUTPUT_DIR/bin"

download_and_verify() {
  local url="$1"
  local archive="$2"
  local expected_sha="$3"
  if [[ ! -f "$archive" ]]; then
    echo "Downloading $(basename "$archive")…"
    curl -L --http1.1 --fail --show-error "$url" -o "$archive"
  fi
  local actual_sha
  actual_sha="$(/usr/bin/shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "error: OpenCode archive checksum mismatch: $archive" >&2
    echo "expected: $expected_sha" >&2
    echo "actual:   $actual_sha" >&2
    exit 1
  fi
}

download_and_verify \
  "$RELEASE_BASE/opencode-darwin-arm64.zip" \
  "$ARM64_ARCHIVE" \
  "$ARM64_SHA256"
download_and_verify \
  "$RELEASE_BASE/opencode-darwin-x64-baseline.zip" \
  "$X86_64_ARCHIVE" \
  "$X86_64_SHA256"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/arm64" "$WORK_DIR/x86_64"
/usr/bin/unzip -q "$ARM64_ARCHIVE" -d "$WORK_DIR/arm64"
/usr/bin/unzip -q "$X86_64_ARCHIVE" -d "$WORK_DIR/x86_64"

ARM64_BINARY="$WORK_DIR/arm64/opencode"
X86_64_BINARY="$WORK_DIR/x86_64/opencode"
[[ -x "$ARM64_BINARY" ]] || { echo "error: arm64 archive has no opencode executable" >&2; exit 1; }
[[ -x "$X86_64_BINARY" ]] || { echo "error: x86_64 archive has no opencode executable" >&2; exit 1; }
[[ "$(/usr/bin/lipo -archs "$ARM64_BINARY")" == *arm64* ]] \
  || { echo "error: official arm64 asset has the wrong architecture" >&2; exit 1; }
[[ "$(/usr/bin/lipo -archs "$X86_64_BINARY")" == *x86_64* ]] \
  || { echo "error: official x86_64 asset has the wrong architecture" >&2; exit 1; }

/usr/bin/lipo -create "$ARM64_BINARY" "$X86_64_BINARY" -output "$OUTPUT_DIR/bin/opencode"
chmod 755 "$OUTPUT_DIR/bin/opencode"
/usr/bin/lipo "$OUTPUT_DIR/bin/opencode" -verify_arch arm64 x86_64

HOST_VERSION="$($OUTPUT_DIR/bin/opencode --version 2>/dev/null | head -1)"
[[ "$HOST_VERSION" == "$VERSION" ]] \
  || { echo "error: bundled OpenCode reports $HOST_VERSION; expected $VERSION" >&2; exit 1; }
UNIVERSAL_SHA256="$(/usr/bin/shasum -a 256 "$OUTPUT_DIR/bin/opencode" | awk '{print $1}')"

printf '%s\n' \
  "OpenCode embedded for Mira AI Mode" \
  "Version: $VERSION" \
  "Official release: https://github.com/anomalyco/opencode/releases/tag/v$VERSION" \
  "Architectures: $(/usr/bin/lipo -archs "$OUTPUT_DIR/bin/opencode")" \
  "arm64 archive SHA-256: $ARM64_SHA256" \
  "x86_64 archive SHA-256: $X86_64_SHA256" \
  "Universal binary SHA-256: $UNIVERSAL_SHA256" \
  > "$OUTPUT_DIR/BUILD-INFO.txt"

echo "Built OpenCode $VERSION Universal 2 payload:"
file "$OUTPUT_DIR/bin/opencode"
du -sh "$OUTPUT_DIR"
