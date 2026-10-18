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

# assert_extras_off <config> — no Security & Backup Extra is on (absent or off).
assert_extras_off() {
  jq -e '(.post_install.security.firewall // "none") == "none"
    and ([.post_install // {} | .. | booleans | select(.)] | length) == 0' \
    <<<"$1" >/dev/null
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

# ── a blank session installs nothing personal (ADR 0157) ─────────────────────

# guided_blank [answer…] — the headless replay's pre-disk config for a session
# that never picks a profile.
guided_blank() {
  local answers="$BATS_TEST_TMPDIR/answers"
  printf '%s\n' "$@" >"$answers"
  guided_load_replay "$answers"
  _GUIDED_STATE="$(config_state_new)"
  _guided_shell_set_identity
  _guided_shell_users_reset
  _guided_shell_replay_edits
  skeleton_flatten_devices "$(_guided_shell_effective)"
}

# personal_names — every package and program of the Fleet Layer and aquastias.
personal_names() {
  {
    jsonc_strip "$INSTALLER_DIR/hosts/fleet/profile.jsonc" | jq -r '
      ([.packages.repo // {}, .packages.aur // {}] | .[] | .[] | .[]),
      (.host_programs // [])[]'
    jsonc_strip "$INSTALLER_DIR/users/aquastias/profile.jsonc" \
      | jq -r '(.programs // [])[]'
  } | sort -u
}

@test "a blank session presets nothing personal" {
  local config; config="$(guided_blank new_user_name=guest)"
  jq -e '.system.hostname == "archlinux"' <<<"$config"
  jq -e '.users == ["guest"]' <<<"$config"
  jq -e '(.environment.desktop // []) == []' <<<"$config"
  assert_extras_off "$config"
  jq -e '.system.timezone == null' <<<"$config"     # autodetected (ADR 0118)
  [ -z "$(install_config_from_json "$config" mirror_countries)" ]
}

@test "a blank session installs no Fleet Layer or aquastias software" {
  local config leaked
  config="$(guided_blank new_user_name=guest)"
  leaked="$(package_resolver_resolve "$config" \
    | awk -F '\t' '$1 ~ /^(repo|aur|host-programs|user-programs)$/ {
        print $3 }' | sort -u | grep -xF -f <(personal_names) || true)"
  [ -z "$leaked" ] || { echo "leaks: $leaked"; return 1; }
}

@test "a blank session with one desktop lands it stock" {
  local config; config="$(guided_blank new_user_name=guest desktop=kde)"
  [ "$(install_config_from_json "$config" stock)" = true ]
}

@test "Proceed with no user is refused" {
  run guided_blank
  local answers="$BATS_TEST_TMPDIR/answers"
  printf '%s\n' disk=/dev/disk/by-id/wwn-0xDEAD confirm=INSTALL >"$answers"
  live_medium_disks() { :; }
  picker_enum_disks() { printf '%s\n' /dev/disk/by-id/wwn-0xDEAD; }
  guided_load_replay "$answers"
  run guided_build
  [ "$status" -ne 0 ]
  [[ "$output" == *"no user"* ]]
}
