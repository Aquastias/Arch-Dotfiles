#!/usr/bin/env bash
# Run the bats tests under .installer/tests/ (recursively, so folder-mirrored
# subdirs like config/ are discovered). Vendors bats-core on first run.
#
# Modes (ADR 0046 two-tier + ADR 0078 gate split; --changed ADR 0103):
#   run.sh                Full always-on tier: every bats file (default).
#   run.sh --full         Same as no arg.
#   run.sh --fast         Curated install-correctness subset for a pre-push
#                         gate: config + the validator tier + layout + zfs +
#                         wipe. Skips slow, low-install-risk suites.
#   run.sh --changed [R]  Only the tests for the changed code (a Change-Targeted
#                         Run): git diff (working-tree+staged vs HEAD +
#                         untracked; or vs the optional ref R) mapped to tests,
#                         always unioned with the --fast core, widening to
#                         --full on a broad-blast or unmapped change.
#   run.sh --vm           On-demand VM smoke via matrix.sh (needs KVM). Errors
#                         cleanly where /dev/kvm is absent.
#
# The <90 s wall target (ADR 0048/0078) is aspirational and only trustworthy
# on an idle box; on a loaded dev box judge by total CPU, not wall.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="${BATS_DIR:-$HERE/bats}"

# shellcheck source=./select-changed.sh
source "$HERE/select-changed.sh"   # select_changed_targets + _FAST_CORE_TOKENS

MODE="full"
CHANGED_REF=""
case "${1:-}" in
  --fast) MODE="fast" ;;
  --full | "") MODE="full" ;;
  --changed) MODE="changed"; CHANGED_REF="${2:-}" ;;
  --vm) MODE="vm" ;;
  -h | --help)
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown mode: $1 (want --fast|--full|--changed|--vm)" >&2
    exit 2
    ;;
esac

if [[ "$MODE" == "vm" ]]; then
  exec "$HERE/../tools/matrix.sh" run --smoke
fi

if [[ ! -x "$BATS_DIR/bin/bats" ]]; then
  echo "Vendoring bats-core into $BATS_DIR..."
  git clone --depth 1 https://github.com/bats-core/bats-core.git "$BATS_DIR"
fi

if ! command -v parallel >/dev/null 2>&1; then
  echo "GNU parallel is required. Install: sudo pacman -S parallel" >&2
  exit 1
fi

# expand_tokens <token>... — append the .bats files a target token names to
# FILES. A token ending in .bats is a tests/-relative file; otherwise it is a
# tests/ subdir whose .bats files are all included. The Install-Correctness Core
# (the --fast set) lives as _FAST_CORE_TOKENS in select-changed.sh — one source
# of truth shared by --fast and --changed, so the two cannot drift.
expand_tokens() {
  local t f
  for t in "$@"; do
    if [[ "$t" == *.bats ]]; then
      [[ -f "$HERE/$t" ]] && FILES+=("$HERE/$t")
    else
      while IFS= read -r f; do FILES+=("$f"); done \
        < <(find "$HERE/$t" -name '*.bats' | sort)
    fi
  done
}

collect_all() {
  # Every .bats under tests/ except the vendored bats-core checkout.
  local f
  while IFS= read -r f; do FILES+=("$f"); done \
    < <(find "$HERE" -name '*.bats' -not -path "$BATS_DIR/*" | sort)
}

collect_fast() { expand_tokens "${_FAST_CORE_TOKENS[@]}"; }

collect_changed() {
  # Map the git diff to targets via the pure resolver, then expand. Widen to
  # the full run on a Broad-Blast Path or any unmapped change (fail-safe).
  local root; root="$(cd "$HERE/../.." && pwd)"   # .installer/tests → repo root
  local -a changed=()
  if [[ -n "$CHANGED_REF" ]]; then
    while IFS= read -r p; do changed+=("$p"); done \
      < <(git -C "$root" diff --name-only "$CHANGED_REF")
  else
    while IFS= read -r p; do changed+=("$p"); done \
      < <(git -C "$root" diff --name-only HEAD
          git -C "$root" ls-files --others --exclude-standard)
  fi
  local targets
  targets="$(select_changed_targets ${changed[@]+"${changed[@]}"})"
  if [[ "$targets" == "--full" ]]; then
    echo "[run.sh] --changed: broad-blast or unmapped change → widening to --full" >&2
    collect_all
  else
    echo "[run.sh] --changed targets (+ install-correctness core):" >&2
    sed 's/^/[run.sh]   /' <<< "$targets" >&2
    local t; while IFS= read -r t; do expand_tokens "$t"; done <<< "$targets"
  fi
}

FILES=()
case "$MODE" in
  fast)    collect_fast ;;
  changed) collect_changed ;;
  *)       collect_all ;;
esac

# Dedupe (a changed test file may also be pulled in by its directory token).
if ((${#FILES[@]})); then
  IFS=$'\n' read -r -d '' -a FILES < <(printf '%s\n' "${FILES[@]}" | sort -u && printf '\0')
fi

echo "[run.sh] mode=$MODE files=${#FILES[@]}" >&2
"$BATS_DIR/bin/bats" --jobs "$(nproc)" "${FILES[@]}"
