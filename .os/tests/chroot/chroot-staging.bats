#!/usr/bin/env bats
# Tests for the Chroot Staging Manifest in lib/chroot.sh — the declared set of
# lib/ files staged into the chroot, kept lockstep-checkable here instead of in
# the VM. Catches the lib-foldering breakage (a moved/renamed src) at bats time.

setup() {
  TEST_DIR="$(mktemp -d)"
  OS_DIR="$BATS_TEST_DIRNAME/../.."
  export SCRIPT_DIR="$OS_DIR"

  # chroot.sh references these inside function bodies only; stub for safety.
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; exit 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/chroot.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Echoes the dst basename for each entry in a named manifest array.
_staged_basenames() {
  local -n _arr="$1"
  local entry src dst
  for entry in "${_arr[@]}"; do
    IFS='|' read -r src dst <<< "$entry"
    basename "$dst"
  done
}

# ── every manifest src exists (catches a moved/renamed lib file) ─────────────

@test "every _CHROOT_STAGE_LIBCHROOT src exists in the repo" {
  local entry src dst
  for entry in "${_CHROOT_STAGE_LIBCHROOT[@]}"; do
    IFS='|' read -r src dst <<< "$entry"
    [ -f "$OS_DIR/$src" ] || { echo "missing src: $src"; false; }
  done
}

@test "every _CHROOT_STAGE_EXTRAS_LIB src exists in the repo" {
  local entry src dst
  for entry in "${_CHROOT_STAGE_EXTRAS_LIB[@]}"; do
    IFS='|' read -r src dst <<< "$entry"
    [ -f "$OS_DIR/$src" ] || { echo "missing src: $src"; false; }
  done
}

# ── _chroot_stage materializes entries to the right dst ──────────────────────

@test "_chroot_stage copies each entry to dst-root, creating parent dirs" {
  _chroot_stage "$TEST_DIR/out" "${_CHROOT_STAGE_EXTRAS_LIB[@]}"
  [ -f "$TEST_DIR/out/common.sh" ]
  [ -f "$TEST_DIR/out/jsonc.sh" ]
  [ -f "$TEST_DIR/out/config/categorized-list.sh" ]
  [ -f "$TEST_DIR/out/chroot/extras-common.sh" ]
}

@test "_chroot_stage flattens lib-chroot siblings to bare basenames" {
  _chroot_stage "$TEST_DIR/lc" "${_CHROOT_STAGE_LIBCHROOT[@]}"
  [ -f "$TEST_DIR/lc/install-state.sh" ]
  [ -f "$TEST_DIR/lc/kernel.sh" ]
  [ -f "$TEST_DIR/lc/grub-common.sh" ]
}

# ── lockstep: staged-sibling sources in lib/chroot/* ⊆ the manifest ──────────
# Each chroot script's first-choice path for a staged sibling is
# "$_LIB_DIR/<name>.sh" (the "../" form is the source-tree fallback). Every such
# referenced basename must be provided by _CHROOT_STAGE_LIBCHROOT, else the
# chroot would source a file nobody staged — a failure only the VM would catch.

@test "every \$_LIB_DIR sibling sourced by lib/chroot/* is in the manifest" {
  local staged
  staged="$(_staged_basenames _CHROOT_STAGE_LIBCHROOT)"

  local refs name
  refs="$(grep -rhoE '_LIB_DIR[}]?/[a-z0-9][a-z0-9-]*\.sh' \
    "$OS_DIR"/lib/chroot/*.sh | sed -E 's#.*/##' | sort -u)"

  [ -n "$refs" ]  # sanity: the grep found references
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    # A file that actually lives in lib/chroot/ is staged by the cp -r tree.
    [[ -f "$OS_DIR/lib/chroot/$name" ]] && continue
    grep -qxF "$name" <<< "$staged" \
      || { echo "sourced sibling not staged: $name"; false; }
  done <<< "$refs"
}
