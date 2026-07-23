#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_SCRIPT="$ROOT_DIR/build.sh"
MODE="${1:---source}"

APP_VERSION="$(sed -n 's/^APP_VERSION="\([^"]*\)"$/\1/p' "$BUILD_SCRIPT" | head -1)"
APP_BUILD_BASE="$(sed -n 's/^APP_BUILD_BASE="\([^"]*\)"$/\1/p' "$BUILD_SCRIPT" | head -1)"
MODEL_VERSION="$(sed -n 's/^let appVersionString = .* ?? "\([^"]*\)"$/\1/p' "$ROOT_DIR/Sources/321Doit/Models.swift" | head -1)"
MODEL_BUILD="$(sed -n 's/^let appBuildNumberString = .* ?? "\([^"]*\)"$/\1/p' "$ROOT_DIR/Sources/321Doit/Models.swift" | head -1)"

if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+([.][0-9]+)?$' ]]; then
  echo "error: invalid APP_VERSION in build.sh: $APP_VERSION" >&2
  exit 1
fi
if [[ ! "$APP_BUILD_BASE" =~ '^[1-9][0-9]*$' ]]; then
  echo "error: APP_BUILD_BASE must be a positive integer: $APP_BUILD_BASE" >&2
  exit 1
fi
if [[ "$APP_VERSION" != "$MODEL_VERSION" || "$APP_BUILD_BASE" != "$MODEL_BUILD" ]]; then
  echo "error: build.sh ($APP_VERSION baseline $APP_BUILD_BASE) and Models.swift fallbacks ($MODEL_VERSION build $MODEL_BUILD) differ" >&2
  exit 1
fi

case "$MODE" in
  --source)
    echo "  · version source consistent: $APP_VERSION build baseline $APP_BUILD_BASE"
    ;;
  --built-app)
    APP_DIR="${2:-$ROOT_DIR/build/321Doit.app}"
    INFO_PLIST="$APP_DIR/Contents/Info.plist"
    if [[ ! -f "$INFO_PLIST" ]]; then
      echo "error: built app Info.plist not found: $INFO_PLIST" >&2
      exit 1
    fi
    BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
    BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
    EXPECTED_VERSION="${EXPECTED_APP_VERSION:-$APP_VERSION}"
    EXPECTED_BUILD="${EXPECTED_APP_BUILD:-}"
    if [[ "$BUILT_VERSION" != "$EXPECTED_VERSION" ]]; then
      echo "error: built app version is $BUILT_VERSION; expected $EXPECTED_VERSION" >&2
      exit 1
    fi
    if [[ ! "$BUILT_BUILD" =~ '^[1-9][0-9]*$' ]] || (( BUILT_BUILD < APP_BUILD_BASE )); then
      echo "error: built app Build is invalid or below baseline: $BUILT_BUILD" >&2
      exit 1
    fi
    if [[ -n "$EXPECTED_BUILD" && "$BUILT_BUILD" != "$EXPECTED_BUILD" ]]; then
      echo "error: built app is $BUILT_VERSION build $BUILT_BUILD; expected build $EXPECTED_BUILD" >&2
      exit 1
    fi
    echo "  · built app version verified: $BUILT_VERSION build $BUILT_BUILD"
    ;;
  *)
    echo "usage: $0 [--source | --built-app [app-path]]" >&2
    exit 2
    ;;
esac
