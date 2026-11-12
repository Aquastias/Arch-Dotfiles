#!/usr/bin/env bats
# A Guided profile pick installs exactly what `install.sh --profile <name>`
# installs (ADR 0157). Both front-ends run against the REAL tree; each side is
# normalised the same way (every Install Config field through its accessor, the
# machine facts as sorted JSON, the Package Resolver set), so an explicit
# default and an absent one read the same and disks never enter the compare.

load ../lib/json-helpers

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
  local no_firewall='(.post_install.security.firewall // "none") == "none"'
  local no_flag='[.post_install // {} | .. | booleans | select(.)] == []'
  # No firewall, and no true flag anywhere under post_install.
  json_satisfies "$1" "$no_firewall and $no_flag"
}

# equivalence_text <config-json> — every accessor's value (lines joined with
# commas), then the resolved packages, as sorted "source<TAB>package" lines.
equivalence_text() {
  local config="$1" name values
  for name in $(install_config_schema_names); do
    values="$(install_config_from_json "$config" "$name" | paste -sd, -)"
    printf '%s=%s\n' "$name" "$values"
  done
  # Each package with its source, each once.
  package_resolver_resolve "$config" | cut -f1,3 | sort -u
}

# equivalence_fields <config-json> — the normalised config fields, as JSON.
equivalence_fields() {
  printf '%s\n' "$1" | jq -c -f "$BATS_TEST_DIRNAME/equivalence-fields.jq"
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

# assert_equivalent <name> — `--profile <name>` and a Guided pick of <name>
# install the same: identical accessors and packages, equal fields.
assert_equivalent() {
  local cli guided cli_fields guided_fields
  cli="$(cli_profile "$1")"
  guided="$(guided_pick "$1")"
  diff <(equivalence_text "$cli") <(equivalence_text "$guided") || return 1
  cli_fields="$(equivalence_fields "$cli")"
  guided_fields="$(equivalence_fields "$guided")"
  # The fields are equal (jq's == ignores key order).
  json_satisfies "$cli_fields" ". == $guided_fields" \
    || { diff <(printf '%s\n' "$cli_fields") <(printf '%s\n' "$guided_fields")
         return 1; }
}

@test "Guided pick ≡ --profile: desktop"       { assert_equivalent desktop; }
@test "Guided pick ≡ --profile: laptop"        { assert_equivalent laptop; }
@test "Guided pick ≡ --profile: minimal"       { assert_equivalent minimal; }
@test "Guided pick ≡ --profile: kde-pure"      { assert_equivalent kde-pure; }
@test "Guided pick ≡ --profile: niri-pure"     { assert_equivalent niri-pure; }
@test "Guided pick ≡ --profile: umbriel-pure"  { assert_equivalent umbriel-pure; }
@test "Guided pick ≡ --profile: hyprland-pure" {
  assert_equivalent hyprland-pure
}

@test "Guided pick ≡ --profile: every VM fixture" {
  local directory name
  for directory in "$INSTALLER_DIR"/hosts/vm/*/; do
    name="$(basename "$directory")"
    assert_equivalent "$name" || { echo "differs: $name"; return 1; }
  done
}

@test "picking minimal carries no Host Core packages and no extras" {
  local config; config="$(guided_pick minimal)"
  # No package row comes from the repo or aur layers.
  package_resolver_resolve "$config" | cut -f1 | grep -qxE 'repo|aur' \
    && return 1
  json_satisfies "$config" '.post_install == null'
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
  local fleet_names='([.packages.repo // {}, .packages.aur // {}]'
  fleet_names+=' | .[] | .[] | .[]), (.host_programs // [])[]'
  {
    # The Fleet Layer's packages and host programs.
    jsonc_strip "$INSTALLER_DIR/hosts/fleet/profile.jsonc" \
      | jq -r "$fleet_names"
    # aquastias's programs.
    jsonc_strip "$INSTALLER_DIR/users/aquastias/profile.jsonc" \
      | jq -r '(.programs // [])[]'
  } | sort -u
}

@test "a blank session presets nothing personal" {
  local config; config="$(guided_blank new_user_name=guest)"
  json_satisfies "$config" '.system.hostname == "archlinux"'
  json_satisfies "$config" '.users == ["guest"]'
  json_satisfies "$config" '(.environment.desktop // []) == []'
  assert_extras_off "$config"
  json_satisfies "$config" \
    '.system.timezone == null'     # autodetected (ADR 0118)
  [ -z "$(install_config_from_json "$config" mirror_countries)" ]
}

@test "a blank session installs no Fleet Layer or aquastias software" {
  local config leaked="" source_name layer package
  local -A personal=()
  config="$(guided_blank new_user_name=guest)"
  while IFS= read -r package; do personal["$package"]=1
  done < <(personal_names)
  # Each package a personal layer would bring, when it is a personal name.
  while IFS=$'\t' read -r source_name layer package; do
    case "$source_name" in
    repo | aur | host-programs | user-programs)
      [[ -n "${personal["$package"]:-}" ]] && leaked+=" $package" ;;
    esac
  done < <(package_resolver_resolve "$config")
  [ -z "$leaked" ] || { echo "leaks:$leaked"; return 1; }
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
