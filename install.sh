#!/bin/bash
# One command to go from a fresh clone to Barsong running:
#
#   ./install.sh
#
# Checks what the build needs, then hands over to build.sh, which builds the app,
# installs it to ~/Applications/Barsong.app and opens it. Run it again to update.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Barsong"
MIN_MACOS="13"      # the app itself
VISUALIZER_MACOS="14.2" # the audio process tap the visualizer needs

step() { printf '\n\033[1m==>\033[0m %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
warn() { printf '\033[33m warning:\033[0m %s\n' "$1" >&2; }
fail() { printf '\033[31m error:\033[0m %s\n' "$1" >&2; exit 1; }

# True when $1 (a version like 14.2) is at least $2.
version_at_least() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$2" ]
}

case "${1:-}" in
-h | --help)
    sed -n '2,7p' "$0" | sed 's|^# \{0,1\}||'
    exit 0
    ;;
"") ;;
*) fail "Unknown option: $1 (try --help)" ;;
esac

step "Checking what's needed"

# macOS only: the app is SwiftUI and AppKit, and the package declares .macOS(.v13).
[ "$(uname -s)" = "Darwin" ] || fail "$APP_NAME is a macOS app, and this is $(uname -s)."

macos="$(sw_vers -productVersion)"
version_at_least "$macos" "$MIN_MACOS" ||
    fail "$APP_NAME needs macOS $MIN_MACOS or later, and this is $macos."
note "macOS $macos"
version_at_least "$macos" "$VISUALIZER_MACOS" ||
    warn "The visualizer needs macOS $VISUALIZER_MACOS or later; everything else works on $macos."

# The build needs a Swift toolchain: Xcode, or just its command line tools.
if ! xcode-select --print-path >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    warn "The Xcode command line tools are missing."
    note "Apple's installer is opening now. When it has finished, run ./install.sh again."
    xcode-select --install || true
    exit 1
fi
if ! swift_version="$(swift --version 2>&1)"; then
    printf '%s\n' "$swift_version" >&2
    fail "The Swift toolchain isn't usable yet. If it mentions a licence, run: sudo xcodebuild -license accept"
fi
note "$(printf '%s' "$swift_version" | head -n 1)"

# Not fatal: Barsong can be built before Spotify is installed, it just can't do much.
if [ ! -d /Applications/Spotify.app ] && [ ! -d "$HOME/Applications/Spotify.app" ]; then
    warn "The Spotify desktop app wasn't found. $APP_NAME controls Spotify, so install it before using the app."
fi

step "Building $APP_NAME"
note "The first build downloads nothing but takes a few minutes."
# build.sh is zsh (always present on macOS) and does the signing and the install.
if [ -x ./build.sh ]; then
    ./build.sh
else
    /bin/zsh ./build.sh
fi

step "Done"
note "$APP_NAME is in ~/Applications and should be running: look for it in the menu bar."
note "macOS will ask to let it control Spotify, and for System Audio Recording the first time"
note "the visualizer opens. Both can be changed later in System Settings > Privacy & Security."
note "For Liked Songs, connect an account under Settings > Spotify Account."
