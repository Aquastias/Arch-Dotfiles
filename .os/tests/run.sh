#!/usr/bin/env bash
# Run all bats tests under .os/tests/. Vendors bats-core on first run.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="$HERE/bats"

if [[ ! -x "$BATS_DIR/bin/bats" ]]; then
  echo "Vendoring bats-core into $BATS_DIR..."
  git clone --depth 1 https://github.com/bats-core/bats-core.git "$BATS_DIR"
fi

"$BATS_DIR/bin/bats" "$HERE"/*.bats
