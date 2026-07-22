#!/bin/zsh
set -euo pipefail

LABEL="com.xiaoliang.codex-balance"
BINARY="$HOME/Library/Application Support/Codex Balance/Codex Balance.app/Contents/MacOS/Codex Balance"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

test -x "$BINARY"
/usr/bin/plutil -lint "$PLIST"
/bin/launchctl print "gui/$UID/$LABEL" | /usr/bin/grep -E 'state =|pid =|last exit code ='
"$BINARY" --print
