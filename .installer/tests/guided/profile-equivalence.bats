#!/usr/bin/env bats
# A Guided profile pick installs exactly what `install.sh --profile <name>`
# installs (ADR 0157). Both front-ends run against the REAL tree; each side is
# normalised the same way (every Install Config field through its accessor, the
# machine facts as sorted JSON, the Package Resolver set), so an explicit
# default and an absent one read the same and disks never enter the compare.

setup() {
  export INSTALLER_DIR; INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  info() { :; }; warn() { :; }; section() { :; }
  error() { echo "[error] $*" >&2; return 1; }
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/config/config-state.sh"
  source "$INSTALLER_DIR/lib/config/emit.sh"
  source "$INSTALLER_DIR/lib/config/menu.sh"
  source "$INSTALLER_DIR/lib/packages/package-resolver.sh"
  source "$INSTALLER_DIR/lib/guided/shell.sh"
}

# equivalence_snapshot <config-json> — the normalised install of a config.
equivalence_snapshot() {
  local config="$1" name values
  for name in $(install_config_schema_names); do
    values="$(install_config_from_json "$config" "$name")"
    printf '%s=%s\n' "$name" "${values//$'\n'/,}"
  done
  # console_font is a schema field the Guided baseline seeds explicitly; its
  # accessor above already compares it, defaults applied.
  jq -S '{system: (.system // {} | del(.console_font)), users, post_install, sysctl, persist, mode, ashift,
    os_pool: (.os_pool | del(.devices)?),
    storage_groups: ((.storage_groups // []) | map(del(.devices))),
    data_pools: ((.data_pools // []) | map(del(.devices)))}' <<<"$config"
  package_resolver_resolve "$config" | awk -F '\t' '{ print $1 "\t" $3 }' \
    | sort -u
}

# guided_pick <name> [answer…] — the headless replay's pre-disk config after
# picking <name> (then any further answers), as Proceed would hand to emit.
guided_pick() {
  local answers="$BATS_TEST_TMPDIR/answers"
  printf '%s\n' "profile=$1" "${@:2}" >"$answers"
  guided_load_replay "$answers"
  _GUIDED_STATE="$(config_state_new)"
  _guided_shell_set_identity
  _guided_shell_users_reset
  _guided_shell_seed_primary_user
  _guided_shell_replay_edits
  skeleton_flatten_devices "$(_guided_shell_effective)"
}

# cli_profile <name> — what `install.sh --profile <name>` would install: the
# --print-config profile plus the assembly's hostname fallback (disks aside).
cli_profile() {
  profile_loader_default_hostname "$1" \
    "$(bash "$INSTALLER_DIR/install.sh" --profile "$1" --print-config 2>/dev/null)"
}

assert_equivalent() {
  diff <(equivalence_snapshot "$(cli_profile "$1")") \
       <(equivalence_snapshot "$(guided_pick "$1")")
}

@test "Guided pick ≡ --profile: desktop"       { assert_equivalent desktop; }
@test "Guided pick ≡ --profile: laptop"        { assert_equivalent laptop; }
@test "Guided pick ≡ --profile: minimal"       { assert_equivalent minimal; }
@test "Guided pick ≡ --profile: kde-pure"      { assert_equivalent kde-pure; }
@test "Guided pick ≡ --profile: niri-pure"     { assert_equivalent niri-pure; }
@test "Guided pick ≡ --profile: hyprland-pure" {
  assert_equivalent hyprland-pure
}

@test "Guided pick ≡ --profile: every VM fixture" {
  local directory name
  for directory in "$INSTALLER_DIR"/hosts/vm/*/; do
    name="${directory%/}"; name="${name##*/}"
    assert_equivalent "$name" || { echo "differs: $name"; return 1; }
  done
}

@test "picking minimal carries no Host Core packages and no extras" {
  local config; config="$(guided_pick minimal)"
  package_resolver_resolve "$config" | grep -qP '^(repo|aur)\t' && return 1
  jq -e '.post_install == null' <<<"$config"
}
