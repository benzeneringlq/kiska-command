#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Fixed camera near the outpost; normal AI/ballistics, invulnerable operator.
# Runs 60 warmup frames then 600 focused rendered frames. Stops after 30s.
exec ./tools/run.sh -- --showcase --capture --benchmark "$@"
