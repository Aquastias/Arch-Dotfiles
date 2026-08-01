#!/usr/bin/env bats
# The guided Packages screen + read-only derived section (ADR 0058).
#
# packages.repo/aur had no menu representation at all: seeding a profile
# carried its whole package payload into Config State where the operator could
# neither see nor deselect it. The screen mirrors the Categorized List shape
# the JSONC already uses — slot → category → package toggles — with three-state
# provenance reusing the existing override dot.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  export OS_DIR="$TEST_DIR"

  mkdir -p "$OS_DIR/hosts/core" "$OS_DIR/users/core"
  cat > "$OS_DIR/hosts/core/profile.jsonc" <<'JSON'
{"users":[],"system_programs":["cups"],
 "packages":{"repo":{"shell":["htop","fzf"],"media":["vlc"]},
             "aur":{"misc":["brave-bin"]}}}
JSON
  printf '{"shell":"/bin/zsh"}\n' > "$OS_DIR/users/core/profile.jsonc"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/seed.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  cfgstate_seed_defaults "$(cfgstate_new)" > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }
state()   { cat "$GUIDED_STATE_FILE"; }

# ── the Packages category drills repo / aur / derived ───────────────────────

@test "Packages category lists repo, aur and derived with counts" {
  set_nav "$(nav_to_category Packages)"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^repo ▸ 3 packages'
  echo "$output" | grep -qE '^aur ▸ 1 package'
  echo "$output" | grep -qE '^derived ▸ [0-9]+ packages \(read-only\)'
}

@test "Enter on repo drills to its category list with counts" {
  set_nav "$(nav_to_category Packages)"
  run guided_ctl_enter "repo ▸ 3 packages"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pkgcat" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" slot)" = "repo" ]

  run guided_ctl_list
  echo "$output" | grep -qx "shell ▸ 2"
  echo "$output" | grep -qx "media ▸ 1"
}

@test "aur drills the same way" {
  set_nav "$(nav_to_pkgslot Packages aur)"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "misc ▸ 1"
}

@test "Enter on a category drills to its package toggles" {
  set_nav "$(nav_to_pkgslot Packages repo)"
  run guided_ctl_enter "shell ▸ 2"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pkgs" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" pkgcat)" = "shell" ]
}

# ── three-state provenance ──────────────────────────────────────────────────

@test "an inherited package renders checked with NO override dot" {
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_list
  echo "$output" | grep -qx "\[x\] htop"
  echo "$output" | grep -qx "\[x\] fzf"
  ! echo "$output" | grep -q "htop  ●"
}

@test "a package added this session renders checked WITH a dot" {
  printf '%s\n' '{"packages":{"repo":{"shell":["ripgrep"]}}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_list
  echo "$output" | grep -qx "\[x\] ripgrep  ●"
  echo "$output" | grep -qx "\[x\] htop"      # still inherited, no dot
}

@test "unchecking an inherited package writes an exclude entry" {
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_enter "[x] htop"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.packages.exclude' "$GUIDED_STATE_FILE")" = '["htop"]' ]
}

@test "an excluded package renders unchecked WITH a dot" {
  printf '%s\n' '{"packages":{"exclude":["htop"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_list
  echo "$output" | grep -qx "\[ \] htop  ●"
  echo "$output" | grep -qx "\[x\] fzf"
}

@test "re-checking an excluded package removes the exclusion" {
  printf '%s\n' '{"packages":{"exclude":["htop"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_enter "[ ] htop  ●"
  [ "$output" = "refresh" ]
  jq -e '(.packages.exclude // []) | index("htop") | not' "$GUIDED_STATE_FILE"
}

@test "unchecking a session-added package just drops it (no exclude)" {
  printf '%s\n' '{"packages":{"repo":{"shell":["ripgrep"]}}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_enter "[x] ripgrep  ●"
  [ "$output" = "refresh" ]
  jq -e '.packages.repo.shell == []' "$GUIDED_STATE_FILE"
  jq -e 'has("packages") and (.packages | has("exclude") | not)' \
    "$GUIDED_STATE_FILE"
}

# ── the offered set is the declared union ───────────────────────────────────

@test "the toggle list offers the union across core and the profile" {
  printf '%s\n' '{"packages":{"repo":{"shell":["ripgrep"]}}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_list
  # core's two plus the session's one, and nothing else
  [ "$(echo "$output" | grep -c '^\[')" -eq 3 ]
  echo "$output" | grep -q "htop"
  echo "$output" | grep -q "fzf"
  echo "$output" | grep -q "ripgrep"
}

@test "an excluded core package stays offered so it can be re-checked" {
  printf '%s\n' '{"packages":{"exclude":["htop"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_list
  echo "$output" | grep -q "htop"
}

@test "a free-text entry adds a package not in the union" {
  set_nav "$(nav_to_pkgslot Packages repo)"
  run guided_ctl_enter "+ Add package ▸ type a name not in the list"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "packages.repo.extra" ]

  run guided_ctl_enter "" "ripgrep"
  [ "$(jq -c '.packages.repo.extra' "$GUIDED_STATE_FILE")" = '["ripgrep"]' ]
}

@test "the aur free-text entry writes into packages.aur" {
  set_nav "$(nav_to_pkgslot Packages aur)"
  guided_ctl_enter "+ Add package ▸ type a name not in the list" >/dev/null
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "packages.aur.extra" ]
  run guided_ctl_enter "" "some-aur-pkg"
  [ "$(jq -c '.packages.aur.extra' "$GUIDED_STATE_FILE")" = '["some-aur-pkg"]' ]
}

# ── navigation is non-destructive ───────────────────────────────────────────

@test "edits survive leaving and re-entering the screen" {
  set_nav "$(nav_to_pkgs Packages repo shell)"
  guided_ctl_enter "[x] htop" >/dev/null
  guided_ctl_back >/dev/null                      # → pkgcat
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pkgcat" ]
  guided_ctl_back >/dev/null                      # → category
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]

  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_list
  echo "$output" | grep -qx "\[ \] htop  ●"       # still excluded
}

@test "back from pkgs returns to the category list, then to Packages" {
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_back
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pkgcat" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" slot)" = "repo" ]
  run guided_ctl_back
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" category)" = "Packages" ]
}

# Esc is `back`, and back never commits — only Enter mutates state.
@test "edits commit on Enter and not on Esc" {
  set_nav "$(nav_to_pkgs Packages repo shell)"
  run guided_ctl_back
  [ "$(jq -c '.' "$GUIDED_STATE_FILE")" = '{}' ]
}

# ── the read-only derived section (ticket 09) ───────────────────────────────

@test "the derived section lists sources with counts and their origin" {
  printf '%s\n' '{"environment":{"desktop":["kde"],"gpu":["amd"]}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgderived Packages)"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^gpu ▸ [0-9]+   \(from Environment\)'
  echo "$output" | grep -qE '^audio ▸ [0-9]+   \(from Environment\)'
  echo "$output" | grep -qE '^base ▸ [0-9]+'
  echo "$output" | grep -qE '^kernel ▸ [0-9]+   \(from Options\)'
}

@test "the derived section drills to a source's package list" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgderived Packages)"
  run guided_ctl_enter "gpu ▸ 3   (from Environment)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pkgderivedsrc" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" source)" = "gpu" ]

  run guided_ctl_list
  echo "$output" | grep -q "vulkan-radeon"
}

@test "derived entries cannot be toggled" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgderivedsrc Packages gpu)"
  run guided_ctl_enter "    vulkan-radeon"
  [ "$output" = "noop" ]
  [ "$(jq -c '.packages // "none"' "$GUIDED_STATE_FILE")" = '"none"' ]
}

@test "changing the GPU vendor updates the derived section" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgderivedsrc Packages gpu)"
  run guided_ctl_list
  echo "$output" | grep -q "vulkan-radeon"
  ! echo "$output" | grep -q "nvidia-open-dkms"

  printf '%s\n' '{"environment":{"gpu":["nvidia"]}}' > "$GUIDED_STATE_FILE"
  run guided_ctl_list
  echo "$output" | grep -q "nvidia-open-dkms"
  ! echo "$output" | grep -q "vulkan-radeon"
}

@test "changing the desktop selection updates the derived section" {
  printf '%s\n' '{"environment":{"desktop":[]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgderived Packages)"
  run guided_ctl_list
  ! echo "$output" | grep -qE '^audio ▸'

  printf '%s\n' '{"environment":{"desktop":["kde"]}}' > "$GUIDED_STATE_FILE"
  run guided_ctl_list
  echo "$output" | grep -qE '^audio ▸'
}

@test "toggling a backup tool updates the derived section" {
  printf '%s\n' '{"users":["a"],"post_install":{"backup":{"borg":true}}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pkgderived Packages)"
  run guided_ctl_list
  echo "$output" | grep -qE '^backup ▸ [0-9]+   \(from Backup\)'

  printf '%s\n' '{"users":["a"],"post_install":{"backup":
    {"borg":false,"zfs_auto_snapshot":false}}}' > "$GUIDED_STATE_FILE"
  run guided_ctl_list
  ! echo "$output" | grep -qE '^backup ▸'
}

# The section and the CLI inspector share one resolver, so they cannot drift.
@test "the derived section agrees with the Package Resolver" {
  printf '%s\n' '{"environment":{"desktop":["kde"],"gpu":["amd"]}}' \
    > "$GUIDED_STATE_FILE"
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh"

  local eff; eff="$(_ctl_effective "$(state)" "$(cat "$GUIDED_BASELINE_FILE")")"
  local direct menu
  direct="$(pkgres_resolve "$eff" \
    | awk -F'\t' '$2 == "derived" && $1 == "gpu" { print $3 }' | sort -u)"
  set_nav "$(nav_to_pkgderivedsrc Packages gpu)"
  menu="$(guided_ctl_list | sed 's/^ *//;s/ *$//' \
    | grep -vE '^(← Back)?$' | sort -u)"
  [ "$direct" = "$menu" ]
}
