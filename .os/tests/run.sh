#!/usr/bin/env bash
# Run all bats tests under .os/tests/ (recursively, so folder-mirrored
# subdirs like config/ are discovered). Vendors bats-core on first run.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="${BATS_DIR:-$HERE/bats}"

if [[ ! -x "$BATS_DIR/bin/bats" ]]; then
  echo "Vendoring bats-core into $BATS_DIR..."
  git clone --depth 1 https://github.com/bats-core/bats-core.git "$BATS_DIR"
fi

if ! command -v parallel >/dev/null 2>&1; then
  echo "GNU parallel is required. Install: sudo pacman -S parallel" >&2
  exit 1
fi

# Collect every .bats under tests/ (incl. folder-mirrored subdirs like
# config/) but never the vendored bats-core checkout in $BATS_DIR.
mapfile -t TEST_FILES < <(find "$HERE" -name '*.bats' -not -path "$BATS_DIR/*" | sort)
"$BATS_DIR/bin/bats" --jobs "$(nproc)" "${TEST_FILES[@]}"
