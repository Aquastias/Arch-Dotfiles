#!/usr/bin/env bash
# Run the bats tests under .os/tests/ (recursively, so folder-mirrored
# subdirs like config/ are discovered). Vendors bats-core on first run.
#
# Modes (ADR 0046 two-tier + ADR 0078 gate split):
#   run.sh            Full always-on tier: every bats file (default).
#   run.sh --full     Same as no arg.
#   run.sh --fast     Curated install-correctness subset for a pre-push
#                     gate: config + the validator tier + layout + zfs +
#                     wipe. Skips slow, low-install-risk suites.
#   run.sh --vm       On-demand VM smoke via matrix.sh (needs KVM). Errors
#                     cleanly where /dev/kvm is absent.
#
# The <90 s wall target (ADR 0048/0078) is aspirational and only trustworthy
# on an idle box; on a loaded dev box judge by total CPU, not wall.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="${BATS_DIR:-$HERE/bats}"

MODE="full"
case "${1:-}" in
  --fast) MODE="fast" ;;
  --full | "") MODE="full" ;;
  --vm) MODE="vm" ;;
  -h | --help)
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown mode: $1 (want --fast|--full|--vm)" >&2
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

# The validator tier: real generators through real validators
# (systemd-analyze verify, mkinitcpio -n, fstab lint) — ADR 0048. Named
# here so --fast carries it and the regression catalog can reference it.
VALIDATOR_TIER=(
  chroot/mount-unit-validate.bats
  chroot/initcpio-validate.bats
  chroot/fstab-lint.bats
  chroot/chroot-impermanence.bats
  profiles/user-units-validate.bats
  impermanence-common.bats
  lib/validators.bats
  sops.bats
)

# Root-level bats guarding install-correctness classes (live-medium
# exclusion, ERR-trap cleanliness, stable by-id part names) that live at
# tests/ root rather than in a --fast dir. Named so the gate covers them.
FAST_ROOT=(
  live-medium.bats
  wipe-probe.bats
  wipe-live-medium.bats
  wipe-prior-install-state.bats
  commons-part-name.bats
)

collect_fast() {
  # Install-correctness core: the menu→assembly→layout→pool→wipe path plus
  # the validator tier. A regression here can produce a broken install.
  local d f
  for d in config layout zfs wipe; do
    while IFS= read -r f; do FILES+=("$f"); done \
      < <(find "$HERE/$d" -name '*.bats' | sort)
  done
  for f in "${VALIDATOR_TIER[@]}" "${FAST_ROOT[@]}"; do
    [[ -f "$HERE/$f" ]] && FILES+=("$HERE/$f")
  done
}

FILES=()
if [[ "$MODE" == "fast" ]]; then
  collect_fast
else
  # Every .bats under tests/ except the vendored bats-core checkout.
  while IFS= read -r f; do FILES+=("$f"); done \
    < <(find "$HERE" -name '*.bats' -not -path "$BATS_DIR/*" | sort)
fi

echo "[run.sh] mode=$MODE files=${#FILES[@]}" >&2
"$BATS_DIR/bin/bats" --jobs "$(nproc)" "${FILES[@]}"
