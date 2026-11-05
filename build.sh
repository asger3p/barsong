#!/bin/zsh
# Builds Barsong.app and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Barsong
BINARY="$(swift build -c release --show-bin-path)/Barsong"

APP="build/Barsong.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/Barsong"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

pkill -x Barsong 2>/dev/null || true
rm -rf ~/Applications/"Barsong.app"
cp -R "$APP" ~/Applications/
open ~/Applications/"Barsong.app"
echo "Installed to ~/Applications/Barsong.app"
