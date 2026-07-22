#!/bin/zsh
set -euo pipefail

LABEL="com.xiaoliang.codex-balance"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_ROOT="$HOME/Library/Application Support/Codex Balance"

/bin/launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
if [[ -f "$PLIST" ]]; then /bin/rm "$PLIST"; fi
if [[ -d "$INSTALL_ROOT" ]]; then /bin/rm -R "$INSTALL_ROOT"; fi

echo "Codex Balance 浮层已卸载。"
