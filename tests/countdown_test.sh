#!/bin/zsh
set -euo pipefail

source_path="${SOURCE_PATH:-scripts/CodexBalance.swift}"
temp_dir="$(/usr/bin/mktemp -d /tmp/codex-balance-countdown.XXXXXX)"
trap '/bin/rm -rf "$temp_dir"' EXIT

if ! /usr/bin/grep -q 'func remainingDuration' "$source_path" || \
   ! /usr/bin/grep -q 'drawCenteredText(remainingDuration(until: metric?.resetsAt)' "$source_path"; then
  echo "compact metrics must render the reset countdown" >&2
  exit 1
fi

/usr/bin/swiftc -O -framework AppKit -framework CoreGraphics \
  "$source_path" \
  -o "$temp_dir/Codex Balance"
"$temp_dir/Codex Balance" --test-countdown
