#!/usr/bin/env bash
# Replay every brand rule. Safe to run after each upstream merge.
#
#   scripts/brand/apply.sh                  apply all phases
#   scripts/brand/apply.sh --dry-run        show what would change
#   scripts/brand/apply.sh --phase 1        stop after phase 1
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${here}/brand.py" apply "$@"
