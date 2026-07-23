#!/bin/zsh
# Fast developer update path: build and replace the installed .app directly.
# This intentionally does not create a DMG or PKG.
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP="$ROOT_DIR/build/321Doit.app"
DESTINATION="${INSTALL_APP_DIR:-/Applications}/321Doit.app"
PROJECT_ICON_RELATIVE_PATH="Contents/Resources/ProjectIcon.icns"
PROJECT_ICON_CHANGED=0

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/build.sh"
fi

if [[ ! -x "$APP/Contents/MacOS/321Doit" ]]; then
  echo "error: built app is missing: $APP" >&2
  exit 1
fi

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$BUILT_BUILD" =~ '^[1-9][0-9]*$' ]] || {
  echo "error: built app has an invalid Build: $BUILT_BUILD" >&2
  exit 1
}

if [[ -f "$DESTINATION/Contents/Info.plist" && "${ALLOW_NON_INCREMENTAL_INSTALL:-0}" != "1" ]]; then
  INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
  INSTALLED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$INSTALLED_VERSION" == "$BUILT_VERSION" && "$INSTALLED_BUILD" =~ '^[1-9][0-9]*$' ]] \
    && (( BUILT_BUILD <= INSTALLED_BUILD )); then
    echo "error: refusing non-incremental internal install: $BUILT_VERSION build $BUILT_BUILD is not higher than installed build $INSTALLED_BUILD" >&2
    echo "build again for the next automatic Build, or explicitly set ALLOW_NON_INCREMENTAL_INSTALL=1 for rollback testing" >&2
    exit 1
  fi
fi

if [[ ! -f "$DESTINATION/$PROJECT_ICON_RELATIVE_PATH" ]] \
  || ! cmp -s "$APP/$PROJECT_ICON_RELATIVE_PATH" "$DESTINATION/$PROJECT_ICON_RELATIVE_PATH"; then
  PROJECT_ICON_CHANGED=1
fi

if pgrep -x 321Doit >/dev/null 2>&1; then
  echo "Closing the running 321Doit before updating…"
  defaults write com.321doit.copy 321doit.lifecycle.internalUpdateKeepAndQuit -bool true
  osascript -e 'tell application id "com.321doit.copy" to quit' 2>/dev/null || true
  for _ in {1..20}; do
    pgrep -x 321Doit >/dev/null 2>&1 || break
    sleep 0.25
  done
  defaults delete com.321doit.copy 321doit.lifecycle.internalUpdateKeepAndQuit 2>/dev/null || true
fi

mkdir -p "${DESTINATION:h}"
TEMP="${DESTINATION}.installing"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if (( PROJECT_ICON_CHANGED == 1 )) && [[ -x "$LSREGISTER" && -d "$DESTINATION" ]]; then
  "$LSREGISTER" -u "$DESTINATION" 2>/dev/null || true
fi
rm -rf "$TEMP"
ditto "$APP" "$TEMP"
rm -rf "$DESTINATION"
mv "$TEMP" "$DESTINATION"
xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true

codesign --verify --deep --strict "$DESTINATION"
if [[ -x "$LSREGISTER" ]]; then
  touch "$DESTINATION"
  "$LSREGISTER" -f "$DESTINATION"
fi
if (( PROJECT_ICON_CHANGED == 1 )); then
  # Finder caches document icons by UTI. Restarting Finder only when the
  # project icon itself changed avoids stale artwork without disrupting every
  # internal app update.
  killall Finder 2>/dev/null || true
fi
echo "Updated $DESTINATION to $BUILT_VERSION build $BUILT_BUILD"

if [[ "${OPEN_AFTER_INSTALL:-1}" == "1" ]]; then
  open "$DESTINATION"
fi
