#!/bin/zsh
# Build self-contained Universal 2 FFmpeg/FFprobe command-line tools for the
# offline 321Doit installer.  No Homebrew libraries are linked into the result.
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="8.1.2"
ARCHIVE="$ROOT_DIR/Vendor/FFmpeg/source/ffmpeg-${VERSION}.tar.xz"
ARCHIVE_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
WORK_DIR="$ROOT_DIR/build/ffmpeg-${VERSION}"
OUTPUT_DIR="$ROOT_DIR/Vendor/FFmpeg"
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || print /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
DEPLOY_TARGET="13.0"

mkdir -p "$ROOT_DIR/Vendor/FFmpeg/source" "$OUTPUT_DIR/bin"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Downloading official FFmpeg ${VERSION} source…"
  curl -L --http1.1 --fail --show-error "$SOURCE_URL" -o "$ARCHIVE"
fi

ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$ARCHIVE_SHA256" ]]; then
  echo "error: FFmpeg source checksum mismatch" >&2
  echo "expected: $ARCHIVE_SHA256" >&2
  echo "actual:   $ACTUAL_SHA" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/source"
tar -xf "$ARCHIVE" -C "$WORK_DIR/source" --strip-components=1

build_arch() {
  local arch="$1"
  local build_dir="$WORK_DIR/build-$arch"
  local prefix="$WORK_DIR/prefix-$arch"
  local cross=()
  local asm=()

  [[ "$arch" != "$(uname -m)" ]] && cross+=(--enable-cross-compile)
  [[ "$arch" == "x86_64" ]] && asm+=(--disable-x86asm)

  mkdir -p "$build_dir" "$prefix"
  pushd "$build_dir" >/dev/null
  "$WORK_DIR/source/configure" \
    --prefix="$prefix" \
    --target-os=darwin \
    --arch="$arch" \
    --cc=clang \
    --sysroot="$SDK" \
    --extra-cflags="-arch $arch -mmacosx-version-min=$DEPLOY_TARGET" \
    --extra-ldflags="-arch $arch -mmacosx-version-min=$DEPLOY_TARGET" \
    --disable-shared \
    --enable-static \
    --disable-doc \
    --disable-debug \
    --disable-ffplay \
    --disable-sdl2 \
    --disable-gpl \
    --disable-nonfree \
    --disable-autodetect \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-avfoundation \
    --enable-audiotoolbox \
    --enable-videotoolbox \
    --enable-securetransport \
    "${cross[@]}" \
    "${asm[@]}"
  make -j"${FFMPEG_BUILD_JOBS:-4}" ffmpeg ffprobe
  cp ffmpeg "$prefix/ffmpeg"
  cp ffprobe "$prefix/ffprobe"
  popd >/dev/null
}

build_arch arm64
build_arch x86_64

for tool in ffmpeg ffprobe; do
  lipo -create \
    "$WORK_DIR/prefix-arm64/$tool" \
    "$WORK_DIR/prefix-x86_64/$tool" \
    -output "$OUTPUT_DIR/bin/$tool"
  chmod 755 "$OUTPUT_DIR/bin/$tool"
  [[ "$(lipo -archs "$OUTPUT_DIR/bin/$tool")" == *arm64* ]]
  [[ "$(lipo -archs "$OUTPUT_DIR/bin/$tool")" == *x86_64* ]]
  if otool -L "$OUTPUT_DIR/bin/$tool" | rg -q '/opt/homebrew|/usr/local|/opt/local'; then
    echo "error: $tool still links to a package-manager library" >&2
    otool -L "$OUTPUT_DIR/bin/$tool" >&2
    exit 1
  fi
done

cp "$WORK_DIR/source/COPYING.LGPLv2.1" "$OUTPUT_DIR/COPYING.LGPLv2.1"
cp "$WORK_DIR/source/COPYING.LGPLv3" "$OUTPUT_DIR/COPYING.LGPLv3"

CONFIG_LINE="$($OUTPUT_DIR/bin/ffmpeg -hide_banner -version | sed -n '3p' | sed -E 's#--prefix=[^ ]+#--prefix=<build-prefix>#; s#--sysroot=[^ ]+#--sysroot=<macOS SDK>#')"
cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<INFO
FFmpeg version: $VERSION
Official source: $SOURCE_URL
Source SHA-256: $ARCHIVE_SHA256
Architectures: $(lipo -archs "$OUTPUT_DIR/bin/ffmpeg")
Minimum macOS: $DEPLOY_TARGET

$CONFIG_LINE

This build deliberately omits --enable-gpl and --enable-nonfree and does not
link Homebrew/MacPorts libraries. The exact corresponding source archive is
published beside the installer as a separate GitHub Release asset.
INFO

echo "Built offline FFmpeg payload:"
file "$OUTPUT_DIR/bin/ffmpeg" "$OUTPUT_DIR/bin/ffprobe"
du -sh "$OUTPUT_DIR"
