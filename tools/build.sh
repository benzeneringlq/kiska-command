#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel "${BUILD_JOBS:-4}"
ctest --test-dir build --output-on-failure
echo 'Build complete. Run ./tools/run.sh'
