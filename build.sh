#!/bin/bash
# Builds Tack.app from the Swift package.
#
#   ./build.sh            build build/Tack.app for this Mac
#   ./build.sh install    build, copy to /Applications and launch
#   ./build.sh universal  build a universal (Apple silicon + Intel) app, used for releases
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP=build/Tack.app

if [[ "$MODE" == "universal" ]]; then
  ARCHS=(--arch arm64 --arch x86_64)
  swift build -c release "${ARCHS[@]}"
  BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Tack"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Tack"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tack"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "$MODE" == "install" ]]; then
  pkill -x Tack 2>/dev/null || true
  rm -rf /Applications/Tack.app
  cp -R "$APP" /Applications/
  open /Applications/Tack.app
  echo "Installed to /Applications and launched"
fi
