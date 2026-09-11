#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="CoffeePaste.app"
PROCESS_NAME="CoffeePaste"
SOURCE_APP="$ROOT_DIR/build/Build/Products/Release/$APP_NAME"
INSTALL_DIR="/Applications"
DESTINATION_APP="$INSTALL_DIR/$APP_NAME"
TEMP_APP="$INSTALL_DIR/.$APP_NAME.install.$$"

# 先构建
"$ROOT_DIR/build.sh" "$@"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "error: $SOURCE_APP was not found." >&2
    exit 1
fi

# 停止旧进程
if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    echo "Stopping the running $PROCESS_NAME..."
    pkill -x "$PROCESS_NAME" || true
    for _ in {1..30}; do
        if ! pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
fi

needs_sudo=false
if [[ ! -w "$INSTALL_DIR" ]]; then
    needs_sudo=true
fi

run_privileged() {
    if [[ "$needs_sudo" == true ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

cleanup() {
    run_privileged rm -rf "$TEMP_APP"
}
trap cleanup EXIT

echo "Installing $APP_NAME to $INSTALL_DIR..."
run_privileged rm -rf "$TEMP_APP"
run_privileged ditto "$SOURCE_APP" "$TEMP_APP"
run_privileged rm -rf "$DESTINATION_APP"
run_privileged mv "$TEMP_APP" "$DESTINATION_APP"

trap - EXIT

# 通过 Finder 启动，避免直接执行包内二进制
osascript - "$DESTINATION_APP" <<'APPLESCRIPT'
on run argv
    tell application "Finder" to open (POSIX file (item 1 of argv) as alias)
end run
APPLESCRIPT
echo "Installed and launched: $DESTINATION_APP"