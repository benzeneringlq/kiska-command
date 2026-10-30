#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${GODOT_BIN:-}" ]]; then
  engine="$GODOT_BIN"
elif [[ -x tools/Godot.app/Contents/MacOS/Godot ]]; then
  engine="$PWD/tools/Godot.app/Contents/MacOS/Godot"
elif command -v godot >/dev/null 2>&1; then
  engine=$(command -v godot)
elif command -v godot4 >/dev/null 2>&1; then
  engine=$(command -v godot4)
else
  echo 'Godot 4.5+ required. Run ./tools/bootstrap.sh on macOS, or set GODOT_BIN.' >&2
  exit 1
fi
if [[ ! -f game/.godot/extension_list.cfg || "${RIDGELINE_CHECK_IMPORT:-0}" == 1 ]]; then
  "$engine" --headless --path "$PWD/game" --editor --import --quit > /tmp/ridgeline-import.log 2>&1
  if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load' /tmp/ridgeline-import.log; then
    cat /tmp/ridgeline-import.log
    exit 1
  fi
fi
exec "$engine" --path "$PWD/game" "$@"
