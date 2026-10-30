#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ctest --test-dir build --output-on-failure
log=$(mktemp -t ridgeline-test)
trap 'rm -f "$log"' EXIT
RIDGELINE_CHECK_IMPORT=1 ./tools/run.sh --headless --fixed-fps 60 --quit-after 1800 -- --integration-test > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
grep -q 'INTEGRATION_PASS' "$log"
if grep -Eq 'SCRIPT ERROR|INTEGRATION_FAILED|Parse Error' "$log"; then exit 1; fi
./tools/run.sh --headless --script res://scripts/settings_test.gd -- --settings-test > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
grep -q 'SETTINGS_PASS' "$log"
if grep -Eq 'SCRIPT ERROR|SETTINGS_FAILED|Parse Error' "$log"; then exit 1; fi
./tools/run.sh --headless --fixed-fps 60 --quit-after 6500 -- --logistics-test > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
grep -q 'LOGISTICS_PASS' "$log"
if grep -Eq 'SCRIPT ERROR|LOGISTICS_FAILED|Parse Error' "$log"; then exit 1; fi
./tools/run.sh --headless --fixed-fps 60 --quit-after 4000 -- --vehicle-context-test > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
grep -q 'CONTEXT_PASS' "$log"
if grep -Eq 'SCRIPT ERROR|CONTEXT_FAILED|Parse Error' "$log"; then exit 1; fi

./tools/run.sh --headless --fixed-fps 60 --quit-after 9000 -- --autonomy-test > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
grep -q 'AUTONOMY_PASS' "$log"
if grep -Eq 'SCRIPT ERROR|AUTONOMY_FAILED|Parse Error' "$log"; then exit 1; fi
