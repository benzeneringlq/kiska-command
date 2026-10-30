#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
binding_commit=e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
if [[ ! -f third_party/godot-cpp/CMakeLists.txt ]]; then
  mkdir -p third_party
  git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git third_party/godot-cpp
fi
actual=$(git -C third_party/godot-cpp rev-parse HEAD)
if [[ "$actual" != "$binding_commit" ]]; then
  echo "Expected godot-cpp $binding_commit, found $actual. Use a separate checkout for local binding changes." >&2
  exit 1
fi
if [[ "$(uname -s)" == Darwin && ! -x tools/Godot.app/Contents/MacOS/Godot ]]; then
  archive=$(mktemp -t ridgeline-godot)
  trap 'rm -f "$archive"' EXIT
  curl -L --fail --retry 2 -o "$archive" https://github.com/godotengine/godot/releases/download/4.5.2-stable/Godot_v4.5.2-stable_macos.universal.zip
  unzip -q "$archive" -d tools
fi
echo 'Dependencies ready. Run ./tools/build.sh'
