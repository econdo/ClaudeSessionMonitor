#!/bin/zsh
# Compila la app y genera ClaudeSessionMonitor.app firmada.
#   ./build.sh           → solo compila (build/ClaudeSessionMonitor.app)
#   ./build.sh install   → además la copia a ~/Applications y la abre
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClaudeSessionMonitor"
APP="build/$APP_NAME.app"

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Una identidad estable evita que el llavero vuelva a pedir permiso tras cada compilación.
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}
codesign --force --options runtime --timestamp=none --sign "${IDENTITY:--}" "$APP"
echo "✓ $APP (firmada con: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    ditto "$APP" "$HOME/Applications/$APP_NAME.app"
    open "$HOME/Applications/$APP_NAME.app"
    echo "✓ Instalada en ~/Applications/$APP_NAME.app"
fi
