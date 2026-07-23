#!/bin/zsh
# Developer ID signing + notarization for 321Doit.
#
# Prerequisites:
#   1. Apple Developer account enrolled in the Developer Program
#   2. A "Developer ID Application" certificate in Keychain
#   3. An app-specific password stored in Keychain:
#        xcrun notarytool store-credentials "321DOIT_NOTARY" \
#          --apple-id "YOUR_APPLE_ID" \
#          --team-id "YOUR_TEAM_ID" \
#          --password "YOUR_APP_SPECIFIC_PASSWORD"
#
# Usage:
#   ./notarize.sh                     # sign + notarize + staple
#   ./notarize.sh --skip-notarize     # sign only (offline)
#   SIGNING_IDENTITY="..." ./notarize.sh  # override identity
#
# Output: build/321Doit.app (signed + notarized), dist/321Doit-<version>.dmg
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/321Doit.app"
SKIP_NOTARIZE="${1:-}"
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-321DOIT_NOTARY}"

# Find signing identity
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}' || true)
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "ERROR: No 'Developer ID Application' certificate found in Keychain."
    echo ""
    echo "To set up code signing for 321Doit:"
    echo "  1. Enroll in Apple Developer Program (https://developer.apple.com/programs/)"
    echo "  2. Create a Developer ID Application certificate in Xcode → Settings → Accounts"
    echo "  3. Or set SIGNING_IDENTITY env var to your certificate's Common Name"
    echo ""
    echo "For ad-hoc builds (no notarization), use ./build.sh instead."
    exit 1
fi

if [[ -z "${INSTALLER_SIGNING_IDENTITY:-}" ]]; then
    INSTALLER_SIGNING_IDENTITY=$(security find-identity -v -p basic | grep "Developer ID Installer" | head -1 | awk -F'"' '{print $2}' || true)
fi

if [[ -z "$INSTALLER_SIGNING_IDENTITY" ]]; then
    echo "ERROR: No 'Developer ID Installer' certificate found in Keychain."
    echo "A product installer requires both Developer ID Application and Developer ID Installer certificates."
    exit 1
fi

echo "=== 321Doit Notarization Pipeline ==="
echo "Identity: $SIGNING_IDENTITY"
echo "Installer identity: $INSTALLER_SIGNING_IDENTITY"
echo ""

# Step 1: Build
echo "Step 1/5: Building…"
"$ROOT_DIR/build.sh"
echo ""

# Step 2: Strip ad-hoc signature and re-sign with Developer ID
echo "Step 2/5: Signing with Developer ID…"
codesign --force --deep \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "  ✓ Signed"
echo ""

# Step 3: Package as DMG
echo "Step 3/5: Creating DMG…"
SKIP_APP_BUILD=1 INSTALLER_SIGNING_IDENTITY="$INSTALLER_SIGNING_IDENTITY" "$ROOT_DIR/package.sh"
DMG_PATH=$(ls -t "$DIST_DIR"/321Doit-*.dmg 2>/dev/null | head -1)
if [[ -z "$DMG_PATH" ]]; then
    echo "ERROR: DMG not found after package.sh"
    exit 1
fi

# Re-sign DMG with Developer ID
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
echo "  ✓ DMG signed: $DMG_PATH"
echo ""

if [[ "$SKIP_NOTARIZE" == "--skip-notarize" ]]; then
    echo "Skipping notarization (--skip-notarize flag)."
    echo ""
    echo "=== Done (signed, not notarized) ==="
    echo "App: $APP_DIR"
    echo "DMG: $DMG_PATH"
    exit 0
fi

# Step 4: Notarize
echo "Step 4/5: Submitting to Apple for notarization…"
echo "  (This typically takes 2–10 minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo "  ✓ Notarized"
echo ""

# Step 5: Staple the notarization ticket
echo "Step 5/5: Stapling notarization ticket…"
xcrun stapler staple "$DMG_PATH"
echo "  ✓ Stapled"
echo ""

# Verify everything
echo "Final verification…"
spctl --assess --verbose=4 --type execute "$APP_DIR" 2>&1 || true
xcrun stapler validate "$DMG_PATH"
echo ""

echo "=== Notarization Complete ==="
echo "App: $APP_DIR"
echo "DMG: $DMG_PATH"
echo ""
echo "This DMG can be distributed to any Mac without Gatekeeper warnings."
