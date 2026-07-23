#!/bin/zsh
# Formal offline release pipeline:
#   app + Universal 2 FFmpeg/FFprobe -> macOS product installer -> branded DMG
# Daily development updates should use Tools/install_app.sh instead.
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/321Doit.app"
DIST_DIR="$ROOT_DIR/dist"
INSTALLER_SOURCE="$ROOT_DIR/Tools/Installer"
HOST_ARCH="$(uname -m)"
DEPLOY_TARGET="13.0"
PACKAGE_SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
BG_MODULE_CACHE="$BUILD_DIR/DMGModuleCache-$HOST_ARCH"
PACKAGE_SWIFT_ARGS=(-sdk "$PACKAGE_SDK")
PACKAGE_COMPILER_VERSION="$(swiftc --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)"
if [[ "$HOST_ARCH" == "arm64" ]]; then
  PACKAGE_SDK_INTERFACE="$PACKAGE_SDK/System/Library/Frameworks/AppKit.framework/Modules/AppKit.swiftmodule/arm64e-apple-macos.swiftinterface"
else
  PACKAGE_SDK_INTERFACE="$PACKAGE_SDK/System/Library/Frameworks/AppKit.framework/Modules/AppKit.swiftmodule/x86_64-apple-macos.swiftinterface"
fi
PACKAGE_SDK_VERSION="$(sed -n 's#// swift-compiler-version: Apple Swift version \([0-9][0-9.]*\).*#\1#p' "$PACKAGE_SDK_INTERFACE" 2>/dev/null | head -1)"
PACKAGE_INTERFACE_VERSION="$(sed -n 's#.*-interface-compiler-version \([0-9][0-9.]*\).*#\1#p' "$PACKAGE_SDK_INTERFACE" 2>/dev/null | head -1)"
if [[ -n "$PACKAGE_COMPILER_VERSION" && -n "$PACKAGE_SDK_VERSION" && "$PACKAGE_COMPILER_VERSION" != "$PACKAGE_SDK_VERSION" ]]; then
  [[ -n "$PACKAGE_INTERFACE_VERSION" ]] || {
    echo "error: package Swift $PACKAGE_COMPILER_VERSION and SDK Swift $PACKAGE_SDK_VERSION are incompatible" >&2
    exit 1
  }
  PACKAGE_SWIFT_ARGS+=(-interface-compiler-version "$PACKAGE_INTERFACE_VERSION")
fi

if [[ "${SKIP_RELEASE_TESTS:-0}" != "1" ]]; then
  "$ROOT_DIR/run_rigorous_tests.sh"
fi

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
  REQUIRE_BUNDLED_FFMPEG=1 "$ROOT_DIR/build.sh"
elif [[ ! -x "$APP_DIR/Contents/MacOS/321Doit" ]]; then
  echo "error: SKIP_APP_BUILD=1 but no built app exists at $APP_DIR" >&2
  exit 1
fi

"$ROOT_DIR/Tools/check_internal_version.sh" --built-app "$APP_DIR"
APP_ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/321Doit")"
[[ "$APP_ARCHS" == *arm64* && "$APP_ARCHS" == *x86_64* ]] || {
  echo "error: formal releases require a Universal 2 app ($APP_ARCHS)" >&2
  exit 1
}
codesign --verify --deep --strict "$APP_DIR"
APP_SIGNATURE="$(codesign -dvvv "$APP_DIR" 2>&1)"
[[ "$APP_SIGNATURE" == *"Signature=adhoc"* ]] || {
  echo "error: current release policy requires an ad-hoc app signature" >&2
  exit 1
}
[[ "${APP_SIGNATURE:l}" != *runtime* ]] || {
  echo "error: Hardened Runtime must remain off for the ad-hoc release channel" >&2
  exit 1
}

[[ -s "$ROOT_DIR/dist/sparkle-public.key" ]] || {
  echo "error: dist/sparkle-public.key is required for a release" >&2
  exit 1
}
if [[ ! -s "$ROOT_DIR/dist/sparkle-private.key" && -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "error: a Sparkle private key is required to produce a release candidate" >&2
  exit 1
fi

for tool in ffmpeg ffprobe; do
  TOOL="$APP_DIR/Contents/Resources/Tools/$tool"
  [[ -x "$TOOL" ]] || { echo "error: offline $tool payload is missing" >&2; exit 1; }
  ARCHS="$(lipo -archs "$TOOL")"
  [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || {
    echo "error: $tool is not Universal 2 ($ARCHS)" >&2
    exit 1
  }
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
VOL_NAME="321Doit Installer"
DMG_NAME="321Doit-${VERSION}-build${BUILD_NUMBER}-offline-installer.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
PRODUCT_PKG="$BUILD_DIR/安装 321Doit.pkg"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$DMG_PATH.sha256" "$PRODUCT_PKG"

# 1. Product installer package.
PKG_WORK="$BUILD_DIR/installer"
PKG_ROOT="$PKG_WORK/root"
PKG_SCRIPTS="$PKG_WORK/scripts"
PKG_RESOURCES="$PKG_WORK/resources"
COMPONENT_PKG="$PKG_WORK/321Doit-component.pkg"
rm -rf "$PKG_WORK"
mkdir -p "$PKG_ROOT/Applications" "$PKG_SCRIPTS" "$PKG_RESOURCES"
ditto "$APP_DIR" "$PKG_ROOT/Applications/321Doit.app"
cp "$INSTALLER_SOURCE/preinstall" "$PKG_SCRIPTS/preinstall"
cp "$INSTALLER_SOURCE/postinstall" "$PKG_SCRIPTS/postinstall"
chmod 755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"
cp "$INSTALLER_SOURCE/welcome.html" "$PKG_RESOURCES/welcome.html"
cp "$INSTALLER_SOURCE/license.html" "$PKG_RESOURCES/license.html"
cp "$INSTALLER_SOURCE/conclusion.html" "$PKG_RESOURCES/conclusion.html"

sed "s/@VERSION@/$VERSION/g" \
  "$INSTALLER_SOURCE/Distribution.xml.template" \
  > "$PKG_WORK/Distribution.xml"

pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "com.321doit.copy.pkg" \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$COMPONENT_PKG"

PRODUCTBUILD_ARGS=(
  --distribution "$PKG_WORK/Distribution.xml"
  --resources "$PKG_RESOURCES"
  --package-path "$PKG_WORK"
)
[[ -z "${INSTALLER_SIGNING_IDENTITY:-}" ]] || {
  echo "error: current ad-hoc release policy requires an unsigned PKG; Developer ID Installer migration must be done as one reviewed signing/notarization change" >&2
  exit 1
}
productbuild "${PRODUCTBUILD_ARGS[@]}" "$PRODUCT_PKG"

PKG_SIGNATURE_STATUS="$(pkgutil --check-signature "$PRODUCT_PKG" 2>&1 || true)"
print -r -- "$PKG_SIGNATURE_STATUS"
[[ "$PKG_SIGNATURE_STATUS" == *"Status: no signature"* ]] || {
  echo "error: PKG signature state does not match the current unsigned-installer policy" >&2
  exit 1
}

# 2. Deterministic Retina DMG background.
BG_PNG="$BUILD_DIR/dmg-background.png"
BG_TOOL="$BUILD_DIR/GenerateDMGBackground"
rm -rf "$BG_MODULE_CACHE"
mkdir -p "$BG_MODULE_CACHE"
swiftc \
  -O \
  -j 1 \
  "${PACKAGE_SWIFT_ARGS[@]}" \
  -target "${HOST_ARCH}-apple-macos${DEPLOY_TARGET}" \
  -module-cache-path "$BG_MODULE_CACHE" \
  "$ROOT_DIR/Tools/GenerateDMGBackground.swift" \
  -o "$BG_TOOL" \
  -framework AppKit \
  -framework CoreGraphics
"$BG_TOOL" "$BG_PNG" 760 500

# 3. Writable DMG with one obvious installer entry.
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp "$PRODUCT_PKG" "$STAGING/安装 321Doit.pkg"
cp "$BG_PNG" "$STAGING/.background/background.png"

SIZE_KB="$(du -sk "$STAGING" | awk '{print $1}')"
DMG_SIZE_KB=$((SIZE_KB + 16384))
TMP_DMG="$BUILD_DIR/321Doit-installer-rw.dmg"
rm -f "$TMP_DMG"
hdiutil create \
  -srcfolder "$STAGING" \
  -volname "$VOL_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size "${DMG_SIZE_KB}k" \
  "$TMP_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")"
DEVICE="$(print -r -- "$ATTACH_OUTPUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT_POINT="/Volumes/$VOL_NAME"
[[ -n "$DEVICE" && -d "$MOUNT_POINT" ]] || {
  echo "error: could not mount writable DMG" >&2
  exit 1
}

cleanup_mount() {
  hdiutil detach "$DEVICE" -quiet 2>/dev/null || hdiutil detach "$DEVICE" -force -quiet 2>/dev/null || true
}
trap cleanup_mount EXIT

echo "Applying required Finder background and icon layout…"
osascript <<APPLESCRIPT
tell application "Finder"
  activate
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {200, 120, 960, 648}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set shows icon preview of viewOptions to false
    set shows item info of viewOptions to false
    set background picture of viewOptions to file ".background:background.png"
    set position of item "安装 321Doit.pkg" of container window to {380, 285}
    update without registering applications
    delay 3
    close
  end tell
end tell
APPLESCRIPT

[[ -s "$MOUNT_POINT/.DS_Store" ]] || {
  echo "error: Finder did not write .DS_Store; refusing to ship a background-less DMG" >&2
  exit 1
}
[[ -s "$MOUNT_POINT/.background/background.png" ]] || {
  echo "error: DMG background is missing after layout" >&2
  exit 1
}
chflags hidden "$MOUNT_POINT/.background"

sync
cleanup_mount
trap - EXIT

# 4. Read-only compressed release image, then mount again for structural QA.
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TMP_DMG"
codesign --force --sign - "$DMG_PATH"
codesign --verify "$DMG_PATH"

VERIFY_OUTPUT="$(hdiutil attach -readonly -noverify -noautoopen "$DMG_PATH")"
VERIFY_DEVICE="$(print -r -- "$VERIFY_OUTPUT" | awk '/^\/dev\// {print $1; exit}')"
[[ -f "$MOUNT_POINT/安装 321Doit.pkg" ]]
[[ -s "$MOUNT_POINT/.background/background.png" ]]
[[ -s "$MOUNT_POINT/.DS_Store" ]]
hdiutil detach "$VERIFY_DEVICE" -quiet
hdiutil verify "$DMG_PATH" >/dev/null

DMG_SHA256="$(/usr/bin/shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "$DMG_SHA256  $DMG_NAME" > "$DMG_PATH.sha256"

# A formal release is incomplete without a signed, self-verified appcast
# candidate. Publishing remains a separate explicit step so building an
# internal candidate can never change the public feed accidentally.
APPCAST_ITEM_FILE="$DIST_DIR/321Doit-${VERSION}-build${BUILD_NUMBER}-appcast-item.xml"
APPCAST_CANDIDATE="$DIST_DIR/321Doit-${VERSION}-build${BUILD_NUMBER}-appcast-candidate.xml"
RELEASE_TAG_DEFAULT="v$VERSION-build$BUILD_NUMBER"
RELEASE_TAG="${SPARKLE_RELEASE_TAG:-$RELEASE_TAG_DEFAULT}"
DOWNLOAD_URL_DEFAULT="https://github.com/Maoxintao98/321doit/releases/download/$RELEASE_TAG/$DMG_NAME"
DOWNLOAD_URL="${SPARKLE_DOWNLOAD_URL:-$DOWNLOAD_URL_DEFAULT}"
RELEASE_NOTES_URL_DEFAULT="https://github.com/Maoxintao98/321doit/releases/tag/$RELEASE_TAG"
RELEASE_NOTES_URL="${SPARKLE_RELEASE_NOTES_URL:-$RELEASE_NOTES_URL_DEFAULT}"
zsh "$ROOT_DIR/Tools/sparkle_sign.sh" appcast \
  "$DMG_PATH" \
  --version "$VERSION" \
  --build "$BUILD_NUMBER" \
  --download-url "$DOWNLOAD_URL" \
  --release-notes "$RELEASE_NOTES_URL" \
  > "$APPCAST_ITEM_FILE"

python3 "$ROOT_DIR/Tools/release_preflight.py" \
  --app "$APP_DIR" \
  --dmg "$DMG_PATH" \
  --appcast-item "$APPCAST_ITEM_FILE" \
  --public-key "$ROOT_DIR/dist/sparkle-public.key" \
  --signer "$ROOT_DIR/Tools/sparkle_sign.sh" \
  --feed "$ROOT_DIR/docs/appcast.xml" \
  --candidate "$APPCAST_CANDIDATE" \
  --version "$VERSION" \
  --build "$BUILD_NUMBER"

rm -rf "$STAGING"

echo "Built formal offline installer:"
echo "  PKG: $PRODUCT_PKG"
echo "  DMG: $DMG_PATH"
echo "  SHA-256: $DMG_SHA256"
echo "  Appcast candidate: $APPCAST_CANDIDATE"
echo "For ordinary app updates, run: ./Tools/install_app.sh"
