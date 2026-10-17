#!/usr/bin/env bats
# The Fleet Layer (ADR 0157): the operator's personal software, folded
# Host Core → Fleet Layer → host by `desktop` and `laptop` only. Runs against
# the REAL tree — the point is what the committed profiles resolve to.

setup() {
  export INSTALLER_DIR; INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  source "$INSTALLER_DIR/lib/config/profiles.sh"
  source "$INSTALLER_DIR/lib/packages/package-resolver.sh"
}

# declared_names <profile-file> — every package and Host Program it declares.
declared_names() {
  jsonc_strip "$1" | jq -r '
    ([.packages.repo // {}, .packages.aur // {}] | .[] | .[] | .[]),
    (.host_programs // [])[]' | sort -u
}

fleet_names() { declared_names "$INSTALLER_DIR/hosts/fleet/profile.jsonc"; }

# leaked_names <profile> — Fleet Layer software <profile> installs without
# declaring it itself.
leaked_names() {
  local own
  own="$(profile_loader_directory hosts "$1")/profile.jsonc"
  grep -xF -f <(fleet_names) <(installed_names "$1") \
    | grep -vxF -f <(declared_names "$own") || true
}

# installed_names <profile> — what the Package Resolver installs for it
# through the layered slots (packages + Host Programs) — the only paths the
# Fleet Layer feeds; a derived set (e.g. a Noctalia plugin dep) is not a leak.
installed_names() {
  package_resolver_resolve "$(profile_loader_load "$1")" \
    | awk -F '\t' '$1 ~ /^(repo|aur|host-programs)$/ { print $3 }' \
    | sort -u
}

@test "Host Core declares no packages and no Host Programs" {
  jsonc_strip "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    | jq -e '(.packages // {}) == {} and (.host_programs // []) == []'
}

@test "the Fleet Layer carries the workstation software" {
  fleet_names | grep -qx steam
  fleet_names | grep -qx lact
}

@test "desktop and laptop fold the Fleet Layer" {
  installed_names desktop | grep -qx steam
  installed_names laptop | grep -qx lact
}

@test "no non-fleet committed profile installs Fleet Layer software" {
  local profile leaked
  for profile in minimal kde-pure niri-pure hyprland-pure; do
    leaked="$(leaked_names "$profile")"
    [ -z "$leaked" ] || { echo "$profile leaks: $leaked"; return 1; }
  done
}

@test "no VM fixture installs Fleet Layer software" {
  local directory profile leaked
  for directory in "$INSTALLER_DIR"/hosts/vm/*/; do
    profile="${directory%/}"; profile="${profile##*/}"
    leaked="$(leaked_names "$profile")"
    [ -z "$leaked" ] || { echo "$profile leaks: $leaked"; return 1; }
  done
}

@test "the Fleet Layer is not installable on its own" {
  run profile_loader_load fleet
  [ "$status" -eq 3 ]
}

@test "the Profiles picker does not list the Fleet Layer" {
  ! profiles_list "$INSTALLER_DIR/hosts" | grep -qx fleet
}

# ── neutral User Core: personal programs live on aquastias (ADR 0157) ────────

@test "User Core declares no programs and a bash shell" {
  jsonc_strip "$INSTALLER_DIR/users/core/profile.jsonc" \
    | jq -e '(.programs // []) == [] and .shell == "/bin/bash"'
}

@test "a user with no User Profile resolves to bash and no programs" {
  run profile_loader_load_user nobody-here
  [ "$status" -eq 1 ]
  jq -e '(.programs // []) == [] and .shell == "/bin/bash"' <<<"$output"
}

@test "aquastias keeps zsh and the personal programs" {
  local user; user="$(profile_loader_load_user aquastias)"
  jq -e '.shell == "/bin/zsh"' <<<"$user"
  jq -e '.programs | index("claude") and index("nvim") and index("docker")' \
    <<<"$user"
}

@test "no VM user excludes a program nothing gives it" {
  local file
  for file in "$INSTALLER_DIR"/users/vm/*/profile.jsonc; do
    ! jsonc_strip "$file" | jq -e 'has("programs_exclude")' >/dev/null \
      || { echo "$file"; return 1; }
  done
}

# ── pure profiles: stock userland too (ADR 0157 amending ADR 0112) ──────────

@test "the pure profiles carry no User Program" {
  local profile programs
  for profile in kde-pure niri-pure hyprland-pure; do
    programs="$(package_resolver_resolve "$(profile_loader_load "$profile")" \
      | awk -F '\t' '$1 == "user-programs" { print $3 }')"
    [ -z "$programs" ] || { echo "$profile: $programs"; return 1; }
  done
}

@test "the pure profiles still declare a login user" {
  local profile
  for profile in kde-pure niri-pure hyprland-pure; do
    profile_loader_load "$profile" | jq -e '(.users | length) == 1' >/dev/null \
      || { echo "$profile"; return 1; }
  done
}
