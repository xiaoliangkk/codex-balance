#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
INSTALL_ROOT="$HOME/Library/Application Support/Codex Balance"
APP_ROOT="$INSTALL_ROOT/Codex Balance.app"
MACOS_ROOT="$APP_ROOT/Contents/MacOS"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.xiaoliang.codex-balance.plist"
LABEL="com.xiaoliang.codex-balance"
LOG_PATH="$HOME/Library/Logs/CodexBalance.log"

mkdir -p "$MACOS_ROOT" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
/usr/bin/swiftc -O -framework AppKit -framework CoreGraphics \
  "$SCRIPT_DIR/CodexBalance.swift" \
  -o "$MACOS_ROOT/Codex Balance"
/bin/cp "$SCRIPT_DIR/Info.plist" "$APP_ROOT/Contents/Info.plist"

TEMP_PLIST="$(/usr/bin/mktemp /tmp/codex-balance-launchagent.XXXXXX.plist)"
/usr/bin/plutil -create xml1 "$TEMP_PLIST"
/usr/bin/plutil -insert Label -string "$LABEL" "$TEMP_PLIST"
/usr/bin/plutil -insert ProgramArguments -json "[\"$MACOS_ROOT/Codex Balance\"]" "$TEMP_PLIST"
/usr/bin/plutil -insert RunAtLoad -bool true "$TEMP_PLIST"
/usr/bin/plutil -insert KeepAlive -bool true "$TEMP_PLIST"
/usr/bin/plutil -insert ProcessType -string Interactive "$TEMP_PLIST"
/usr/bin/plutil -insert StandardOutPath -string "$LOG_PATH" "$TEMP_PLIST"
/usr/bin/plutil -insert StandardErrorPath -string "$LOG_PATH" "$TEMP_PLIST"
/bin/mv "$TEMP_PLIST" "$LAUNCH_AGENT"

/bin/launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
/bin/sleep 1
if ! /bin/launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT" 2>/dev/null; then
  /bin/sleep 1
  /bin/launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"
fi
/bin/launchctl kickstart -k "gui/$UID/$LABEL"

"$MACOS_ROOT/Codex Balance" --print
