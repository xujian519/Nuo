#!/usr/bin/env bash
# Brand guard. Fails when the legacy brand grows back outside frozen identifiers,
# when an enforced rule is not absorbed, or when a frozen contract disappears.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${here}/brand.py" verify "$@"
