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

# installed_all <profile> — every package the Package Resolver installs for it.
installed_all() {
  package_resolver_resolve "$(profile_loader_load "$1")" \
    | awk -F '\t' '{ print $3 }' | sort -u
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

@test "no non-fleet VM fixture installs Fleet Layer software" {
  local profile leaked
  for profile in arch-kde arch-data arch-secure; do
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

# ── stock by default: curation is opt-in (ADR 0157) ─────────────────────────

@test "a desktop with no stock key installs stock" {
  [ "$(install_config_from_json '{"environment":{"desktop":["kde"]}}' stock)" \
    = true ]
}

@test "the fleet hosts and curated VM fixtures stay curated" {
  local profile
  for profile in desktop laptop arch-kde arch-niri arch-hyprland arch-combined \
                 arch-combined-sops-impermanence arch-audit; do
    [ "$(install_config_from_json "$(profile_loader_load "$profile")" stock)" \
      = false ] || { echo "$profile"; return 1; }
  done
}

# ── neutral fonts and mirrors: the Fleet Layer carries the operator's ───────

@test "a non-fleet profile installs only the neutral font families" {
  local fonts
  fonts="$(package_resolver_resolve "$(profile_loader_load minimal)" \
    | awk -F '\t' '$1 == "fonts" { print $3 }')"
  grep -qE 'nerd|ttf-ms-fonts' <<<"$fonts" && return 1
  grep -qx noto-fonts <<<"$fonts"
}

@test "a non-fleet profile ranks mirrors worldwide" {
  [ -z "$(install_config_from_json "$(profile_loader_load minimal)" \
    mirror_countries)" ]
}

@test "the fleet hosts keep the full font set and their mirror countries" {
  local config; config="$(profile_loader_load desktop)"
  package_resolver_resolve "$config" | grep -qP '^fonts\t.*\tttf-firacode-nerd$'
  install_config_from_json "$config" mirror_countries | grep -qx Romania
}

# ── stock KDE is plasma-meta, not the curated look (ADR 0157) ───────────────

@test "stock KDE installs no curated shell extras" {
  local packages
  packages="$(installed_all kde-pure)"
  grep -qx plasma-meta <<<"$packages"
  grep -qx papirus-icon-theme <<<"$packages" && return 1
  grep -qx plasma-applets-weather-widget-3 <<<"$packages" && return 1
  return 0
}

@test "curated KDE keeps the curated shell extras" {
  local packages
  packages="$(installed_all arch-kde)"
  grep -qx papirus-icon-theme <<<"$packages"
  grep -qx plasma-applets-weather-widget-3 <<<"$packages"
}

# ── `"fleet": true` marks a fleet host (ADR 0157) ───────────────────────────
# The reference/audit VM fixtures model the operator's machines, so they fold
# the Fleet Layer like desktop and laptop.

@test "the fleet VM fixtures fold the Fleet Layer" {
  local profile
  for profile in arch-audit arch-combined arch-combined-sops-impermanence \
                 arch-hyprland arch-niri; do
    installed_names "$profile" | grep -qx steam \
      || { echo "$profile lacks the Fleet Layer"; return 1; }
  done
}

@test "exactly the declared fleet hosts carry fleet: true" {
  local hosts
  hosts="$(grep -l '"fleet": *true' "$INSTALLER_DIR"/hosts/*/profile.jsonc \
    "$INSTALLER_DIR"/hosts/vm/*/profile.jsonc | awk -F/ '{ print $(NF-1) }' \
    | sort | awk '{ printf "%s ", $0 }')"
  [ "$hosts" = "arch-audit arch-combined arch-combined-sops-impermanence \
arch-hyprland arch-niri desktop laptop " ]
}
