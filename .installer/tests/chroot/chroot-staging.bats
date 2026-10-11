#!/usr/bin/env bats
# Tests for the Chroot Staging Manifest in lib/chroot.sh — the declared set of
# lib/ files staged into the chroot, kept lockstep-checkable here instead of in
# the VM. Catches the lib-foldering breakage (a moved/renamed src) at bats time.

setup() {
  # The Installer Stdlib chroot.sh runs with (path helpers); stubs below win.
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  TEST_DIR="$(mktemp -d)"
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  export SCRIPT_DIR="$INSTALLER_DIR"

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
  local -n staged_entries="$1"
  local entry source_path destination_path
  for entry in "${staged_entries[@]}"; do
    IFS='|' read -r source_path destination_path <<< "$entry"
    printf '%s\n' "${destination_path##*/}"
  done
}

# ── every manifest src exists (catches a moved/renamed lib file) ─────────────

@test "every _CHROOT_STAGE_LIBCHROOT src exists in the repo" {
  local entry source_path destination_path
  for entry in "${_CHROOT_STAGE_LIBCHROOT[@]}"; do
    IFS='|' read -r source_path destination_path <<< "$entry"
    [ -f "$INSTALLER_DIR/$source_path" ] || { echo "missing src: $source_path"; false; }
  done
}

@test "every _CHROOT_STAGE_EXTRAS_LIB src exists in the repo" {
  local entry source_path destination_path
  for entry in "${_CHROOT_STAGE_EXTRAS_LIB[@]}"; do
    IFS='|' read -r source_path destination_path <<< "$entry"
    [ -f "$INSTALLER_DIR/$source_path" ] || { echo "missing src: $source_path"; false; }
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
  [ -f "$TEST_DIR/lc/esp-stage.sh" ]
}

# ── lockstep: staged-sibling sources in lib/chroot/* ⊆ the manifest ──────────
# Each chroot script's first-choice path for a staged sibling is
# "$_LIB_DIR/<name>.sh" (the "../" form is the source-tree fallback). Every such
# referenced basename must be provided by _CHROOT_STAGE_LIBCHROOT, else the
# chroot would source a file nobody staged — a failure only the VM would catch.

@test "every \$_LIB_DIR sibling sourced by lib/chroot/* is in the manifest" {
  local staged
  staged="$(_staged_basenames _CHROOT_STAGE_LIBCHROOT)"

  local references name
  references="$(grep -rhoE '_LIB_DIR[}]?/[a-z0-9][a-z0-9-]*\.sh' \
    "$INSTALLER_DIR"/lib/chroot/*.sh | awk '{ sub(/.*\//, ""); print }' | sort -u)"

  [ -n "$references" ]  # sanity: the grep found references
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    # A file that actually lives in lib/chroot/ is staged by the cp -r tree.
    [[ -f "$INSTALLER_DIR/lib/chroot/$name" ]] && continue
    grep -qxF "$name" <<< "$staged" \
      || { echo "sourced sibling not staged: $name"; false; }
  done <<< "$references"
}

# ── lockstep: lib/ files sourced by extras/**/*.sh ⊆ the extras-lib manifest ──
# Each extras adapter sources a staged lib helper via
# "${SCRIPT_DIR}/../../../lib/<path>", which resolves to /root/lib/<path> inside
# the chroot — but only if _CHROOT_STAGE_EXTRAS_LIB stages it there. A source
# with no matching manifest entry aborts the install inside the chroot ("<file>:
# No such file or directory"), a failure only the VM would catch. This is the
# gap that let the re-added hyprland.sh source lib/chroot/gpu.sh unstaged.

@test "every lib/ file sourced by extras/**/*.sh is in _CHROOT_STAGE_EXTRAS_LIB" {
  local staged_dsts entry source_path destination_path
  staged_dsts=""
  for entry in "${_CHROOT_STAGE_EXTRAS_LIB[@]}"; do
    IFS='|' read -r source_path destination_path <<< "$entry"
    staged_dsts+="${destination_path}"$'\n'
  done

  local references path
  references="$(grep -rhoE '\.\./\.\./\.\./lib/[A-Za-z0-9/_-]+\.sh' "$INSTALLER_DIR"/extras \
    2>/dev/null | awk '{ sub(/.*\.\.\/\.\.\/\.\.\/lib\//, ""); print }' | sort -u)"

  [ -n "$references" ]  # sanity: the grep found extras→lib sources
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    grep -qxF "$path" <<< "$staged_dsts" \
      || { echo "extras sources lib/$path — not in _CHROOT_STAGE_EXTRAS_LIB"; \
           false; }
  done <<< "$references"
}
