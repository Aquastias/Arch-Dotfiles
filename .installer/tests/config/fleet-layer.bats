#!/usr/bin/env bats
# The Fleet Layer (ADR 0157): the operator's personal software, folded
# Host Core → Fleet Layer → host by fleet hosts (`"fleet": true`) only. Runs
# against the REAL tree — the point is what the committed profiles resolve to.

load ../lib/text-helpers
load ../lib/json-helpers

setup() {
  export INSTALLER_DIR; INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  source "$INSTALLER_DIR/lib/config/profiles.sh"
  source "$INSTALLER_DIR/lib/packages/package-resolver.sh"
}

# declared_names <profile-file> — every package and Host Program it declares.
declared_names() {
  local names='([.packages.repo // {}, .packages.aur // {}] | .[] | .[] | .[]),'
  names+=' (.host_programs // [])[]'
  # Every repo and AUR package and Host Program, each once.
  jsonc_strip "$1" | jq -r "$names" | sort -u
}

fleet_names() { declared_names "$INSTALLER_DIR/hosts/fleet/profile.jsonc"; }

# resolved <profile> [source…] — what the Package Resolver installs for
# <profile> (only from the named sources when given), sorted, each once.
resolved() {
  local profile="$1" source_name _layer package
  shift
  # Resolver rows: source, layer, package.
  while IFS=$'\t' read -r source_name _layer package; do
    if (($#)) && ! text_has_line "$(printf '%s\n' "$@")" "$source_name"; then
      continue
    fi
    printf '%s\n' "$package"
  done < <(package_resolver_resolve "$(profile_loader_load "$profile")") \
    | sort -u
}

# leaked_names <profile> — Fleet Layer software <profile> installs without
# declaring it itself.
leaked_names() {
  local own
  own="$(profile_loader_directory hosts "$1")/profile.jsonc"
  # Fleet software it installs (lines in both lists), minus its own.
  comm -12 <(fleet_names) <(installed_names "$1") \
    | comm -23 - <(declared_names "$own")
}

# installed_all <profile> — every package the Package Resolver installs for it.
installed_all() { resolved "$1"; }

# installed_names <profile> — what the Package Resolver installs for it
# through the layered slots (packages + Host Programs) — the only paths the
# Fleet Layer feeds; a derived set (e.g. a Noctalia plugin dep) is not a leak.
installed_names() { resolved "$1" repo aur host-programs; }

@test "Host Core declares no packages and no Host Programs" {
  json_satisfies "$(jsonc_strip "$INSTALLER_DIR/hosts/core/profile.jsonc")" \
    '(.packages // {}) == {} and (.host_programs // []) == []'
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
  for profile in minimal kde-pure niri-pure hyprland-pure umbriel-pure; do
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
  json_satisfies "$(jsonc_strip "$INSTALLER_DIR/users/core/profile.jsonc")" \
    '(.programs // []) == [] and .shell == "/bin/bash"'
}

@test "a user with no User Profile resolves to bash and no programs" {
  run profile_loader_load_user nobody-here
  [ "$status" -eq 1 ]
  output_satisfies '(.programs // []) == [] and .shell == "/bin/bash"'
}

@test "aquastias keeps zsh and the personal programs" {
  local user; user="$(profile_loader_load_user aquastias)"
  json_satisfies "$user" '.shell == "/bin/zsh"'
  json_satisfies "$user" \
    '.programs | index("claude") and index("nvim") and index("docker")'
}

@test "no VM user excludes a program nothing gives it" {
  local file
  for file in "$INSTALLER_DIR"/users/vm/*/profile.jsonc; do
    ! json_satisfies "$(jsonc_strip "$file")" 'has("programs_exclude")' \
      || { echo "$file"; return 1; }
  done
}

# ── pure profiles: stock userland too (ADR 0157 amending ADR 0112) ──────────

@test "the pure profiles carry no User Program" {
  local profile programs
  for profile in kde-pure niri-pure hyprland-pure umbriel-pure; do
    programs="$(resolved "$profile" user-programs)"
    [ -z "$programs" ] || { echo "$profile: $programs"; return 1; }
  done
}

@test "the pure profiles still declare a login user" {
  local profile
  for profile in kde-pure niri-pure hyprland-pure umbriel-pure; do
    json_satisfies "$(profile_loader_load "$profile")" '(.users | length) == 1' \
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
  fonts="$(resolved minimal fonts)"
  # No nerd font and no MS font.
  printf '%s\n' "$fonts" | grep -qE 'nerd|ttf-ms-fonts' && return 1
  text_has_line "$fonts" noto-fonts
}

@test "a non-fleet profile ranks mirrors worldwide" {
  [ -z "$(install_config_from_json "$(profile_loader_load minimal)" \
    mirror_countries)" ]
}

@test "the fleet hosts keep the full font set and their mirror countries" {
  local config; config="$(profile_loader_load desktop)"
  text_has_line "$(resolved desktop fonts)" ttf-firacode-nerd
  install_config_from_json "$config" mirror_countries | grep -qx Romania
}

# ── stock KDE is plasma-meta, not the curated look (ADR 0157) ───────────────

@test "stock KDE installs no curated shell extras" {
  local packages
  packages="$(installed_all kde-pure)"
  text_has_line "$packages" plasma-meta
  text_has_line "$packages" papirus-icon-theme && return 1
  text_has_line "$packages" plasma-applets-weather-widget-3 && return 1
  return 0
}

@test "curated KDE keeps the curated shell extras" {
  local packages
  packages="$(installed_all arch-kde)"
  text_has_line "$packages" papirus-icon-theme
  text_has_line "$packages" plasma-applets-weather-widget-3
}

# ── `"fleet": true` marks a fleet host (ADR 0157) ───────────────────────────
# The reference/audit VM fixtures model the operator's machines, so they fold
# the Fleet Layer like desktop and laptop.

@test "the fleet VM fixtures fold the Fleet Layer" {
  local profile
  for profile in arch-audit arch-combined arch-combined-sops-impermanence \
                 arch-hyprland arch-niri; do
    text_has_line "$(installed_names "$profile")" steam \
      || { echo "$profile lacks the Fleet Layer"; return 1; }
  done
}

@test "exactly the declared fleet hosts carry fleet: true" {
  local file hosts=""
  for file in "$INSTALLER_DIR"/hosts/*/profile.jsonc \
              "$INSTALLER_DIR"/hosts/vm/*/profile.jsonc; do
    json_satisfies "$(jsonc_strip "$file")" '.fleet == true' || continue
    hosts+="$(basename "$(dirname "$file")") "
  done
  [ "$hosts" = "desktop laptop arch-audit arch-combined \
arch-combined-sops-impermanence arch-hyprland arch-niri " ]
}
