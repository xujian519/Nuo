#!/usr/bin/env bash
# Re-measure baseline.json after a phase lands: `scripts/brand/snapshot.sh --write`.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${here}/brand.py" snapshot "$@"
