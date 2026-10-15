#!/bin/zsh
set -euo pipefail

SOURCE_PATH="${SOURCE_PATH:-scripts/CodexBalance.swift}"
MAX_SAFE_WIDTH=48

compact_width="$(/usr/bin/sed -nE 's/.*compactSize = NSSize\(width: ([0-9]+).*/\1/p' "$SOURCE_PATH")"
if [[ -z "$compact_width" || "$compact_width" -gt "$MAX_SAFE_WIDTH" ]]; then
  echo "compact overlay width must be <= ${MAX_SAFE_WIDTH}px, got ${compact_width:-unknown}px" >&2
  exit 1
fi

/usr/bin/swift - "$compact_width" <<'SWIFT'
import AppKit

let containerWidth = Double(CommandLine.arguments[1])!
let fontSize = 10.0
let labelFont = NSFont.systemFont(ofSize: fontSize, weight: .regular)
let valueFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
func width(_ text: String, font: NSFont) -> Double {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}
let required = 4 + width("100%", font: valueFont) + 4
guard required <= containerWidth else {
    fputs("worst-case compact text requires \(required)px, container has \(containerWidth)px\n", stderr)
    exit(1)
}
print("compact layout OK: \(required)px / \(containerWidth)px")
SWIFT
