#!/usr/bin/env bats
# Tests: categories and buckets (split from guided-menu.bats;
# shared setup in guided-menu-helpers.bash)

load guided-menu-helpers


# ── the two-level model: the fourteen Configuration Categories (ADR 0081) ────

@test "menu_categories: returns the categories in install-flow order (ADR 0081)" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 14'
  echo "$output" | jq -e '[.[].name] == ["System","Locales","Users","Disks",
    "Bootloader","Kernels","Environment","Mirrors & Repositories","Pacman",
    "Packages","Daemons","Security","Backup","Expert"]'
}

@test "menu_categories: each category carries its bucket" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .bucket | length > 0)'
  echo "$output" | jq -e '.[] | select(.name == "System")   | .bucket == "GENERAL"'
  echo "$output" | jq -e '.[] | select(.name == "Daemons") | .bucket == "SERVICES"'
  echo "$output" | jq -e '.[] | select(.name == "Expert") | .bucket == "ADVANCED"'
}

@test "menu_categories: each category carries a non-empty summary" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .summary | length > 0)'
  echo "$output" \
    | jq -e '.[] | select(.name == "Security") | .summary | test("firewall")'
}

@test "menu_categories: a fresh state overrides nothing" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .overridden == false)'
}

@test "menu_categories: editing a field flips only its category's ●" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"myhost"')"
  run menu_categories "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "System")  | .overridden == true'
  echo "$output" | jq -e '.[] | select(.name == "Disks")   | .overridden == false'
  echo "$output" | jq -e '.[] | select(.name == "Kernels") | .overridden == false'
}

# the ● folds the override map only — a seeded-but-untouched value carries no ●
@test "menu_categories: a baseline-only value leaves the category unmarked" {
  baseline="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"
  run menu_categories "$(config_state_new)" "$baseline"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "System") | .overridden == false'
}


# ── drill-in: menu_category_rows returns one category's field rows ──────────
# The sub-menu contract: given a category name, the rows for that category only
# (same per-row shape as menu_rows). The baseline still supplies seeded values.

@test "menu_category_rows: System returns only System rows incl. hostname" {
  run menu_category_rows System "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "System")'
  echo "$output" | jq -e 'any(.[]; .field == "system.hostname")'
}

# Font Catalog (ADR 0080): the curated multi-select lives as a System leaf.
@test "menu_category_rows: the Font Catalog is a System row" {
  run menu_category_rows System "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.fonts")'
}

@test "menu_enum_options: the Font Catalog offers the curated set" {
  run menu_enum_options options.fonts
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx ttf-jetbrains-mono-nerd
  echo "$output" | grep -qx otf-monaspace-nerd   # off-by-default still offered
  ! echo "$output" | grep -qx ttf-fira-code       # plain build dropped
}

@test "menu_categories: the System summary mentions fonts" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .name == "System" and (.summary | test("fonts")))'
}


# ── menu_top_lines (ADR 0081): the bucketed top-screen category block ────────
@test "menu_top_lines: emits each bucket header once, before its categories" {
  run menu_top_lines "$(config_state_new)"
  [ "$status" -eq 0 ]
  # every bucket header present, exactly once
  for bucket in "── GENERAL ──" "── STORAGE & BOOT ──" "── SOFTWARE ──" \
           "── SERVICES ──" "── SECURITY & DATA ──" "── ADVANCED ──"; do
    [ "$(grep -Fxc "$bucket" <<<"$output")" -eq 1 ]
  done
  # the GENERAL header leads System, its first category
  awk 'previous == "── GENERAL ──" { print; exit } { previous = $0 }' \
    <<<"$output" | grep -q "^System — "
  # a category line, no header, carries name — summary
  printf '%s\n' "$output" | grep -q "^Daemons — "
}

@test "menu_top_lines: an overridden category carries a trailing ●" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"myhost"')"
  run menu_top_lines "$state"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "^System — .*  ●$"
}

# ADR 0082: a blank spacer line separates one bucket from the next (but not
# before the first bucket header).
@test "menu_top_lines: a blank line separates the buckets" {
  run menu_top_lines "$(config_state_new)"
  [ "$status" -eq 0 ]
  # the line immediately before a non-first bucket header is blank
  [ -z "$(awk '$0 == "── STORAGE & BOOT ──" { print previous; exit }
              { previous = $0 }' <<<"$output")" ]
  # the first line is the first bucket header, not a blank
  [ "${output%%$'\n'*}" = "── GENERAL ──" ]
}


# ── field moves (issue 02): storage knobs surface under Disks ───────────────
# swap / swap_size / esp_size display under Disks (where the operator expects
# storage sizing) while their Config State path stays options.* — the display
# section is independent of the path.

@test "menu_category_rows: esp size surfaces under Disks (swap is synthetic)" {
  run menu_category_rows Disks "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.esp_size")'
  # swap / swap_size moved to the controller's synthetic swap row (sub-editor).
  echo "$output" | jq -e 'all(.[]; .field != "options.swap")'
  echo "$output" | jq -e 'all(.[]; .field != "options.swap_size")'
}

# mirrors + optional repos + custom servers/repos live under Mirrors &
# Repositories (ADR 0071/0072)
@test "menu_category_rows: countries + optional/custom repos under Mirrors & Repositories" {
  run menu_category_rows "Mirrors & Repositories" "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.mirror_countries")'
  echo "$output" | jq -e 'any(.[]; .field == "options.optional_repos")'
  echo "$output" | jq -e 'any(.[]; .field == "options.mirror_servers")'
  echo "$output" | jq -e 'any(.[]; .field == "options.custom_repositories")'
}


# ── Pacman category (ADR 0074): the [options] block flags as a section ───────

@test "menu_categories: Pacman is a category, summary mentions ilovecandy" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .name == "Pacman")'
  echo "$output" \
    | jq -e '.[] | select(.name == "Pacman") | .summary | test("ilovecandy")'
}

@test "menu_category_rows: Pacman carries the six [options] flags with defaults" {
  run menu_category_rows Pacman "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "Pacman")'
  echo "$output" | row options.pacman.ilovecandy | jq -e '.value == "true"'
  echo "$output" | row options.pacman.color | jq -e '.value == "true"'
  echo "$output" | row options.pacman.verbose_pkg_lists | jq -e '.value == "true"'
  echo "$output" | row options.pacman.disable_download_timeout \
    | jq -e '.value == "false"'
  echo "$output" | row options.pacman.no_progress_bar | jq -e '.value == "false"'
  echo "$output" | row options.pacman.parallel_downloads | jq -e '.value == "5"'
  echo "$output" | jq -e 'all(.[]; .overridden == false)'
}

@test "menu_rows: toggling a Pacman flag flips its ● and value" {
  state="$(config_state_set "$(config_state_new)" options.pacman.ilovecandy 'false')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.pacman.ilovecandy | jq -e '.value == "false"'
  echo "$output" | row options.pacman.ilovecandy | jq -e '.overridden == true'
}

@test "menu_categories: editing a Pacman flag flips only the Pacman ●" {
  state="$(config_state_set "$(config_state_new)" options.pacman.color 'false')"
  run menu_categories "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "Pacman") | .overridden == true'
  echo "$output" \
    | jq -e '.[] | select(.name == "Mirrors & Repositories") | .overridden == false'
}

@test "menu_enum_options: optional repositories (multilib + testing)" {
  run menu_enum_options options.optional_repos
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf '%s\n' multilib multilib-testing core-testing extra-testing)" ]
}

# sysctl is kernel hardening, so it lives under Security (ADR 0071); the map
# value renders as comma-joined key=value pairs and flips the Security ● when set.
@test "menu_category_rows: sysctl is a Security row, empty + unmarked when unset" {
  run menu_category_rows Security "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row sysctl | jq -e '.value == ""'
  echo "$output" | row sysctl | jq -e '.overridden == false'
}

@test "menu_rows: a set sysctl renders key=value pairs and is overridden" {
  state="$(config_state_set "$(config_state_new)" sysctl '{"vm.swappiness":10}')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row sysctl | jq -e '.value == "vm.swappiness=10"'
  echo "$output" | row sysctl | jq -e '.overridden == true'
}

# post_install security/backup are their own categories; Packages carries the
# extra-packages row but no host programs row (ADR 0086 — every host program is
# Menu-Owned, so the picker has no members).
@test "menu_category_rows: Packages has no field rows (drill-only)" {
  run menu_category_rows Packages "$(config_state_new)"
  [ "$status" -eq 0 ]
  # Neither extra packages nor host programs — Packages is a pure
  # repo/aur/derived drill now (ADR 0086).
  ! echo "$output" | jq -e 'any(.[]; .field == "packages.repo.extra")'
  ! echo "$output" | jq -e 'any(.[]; .field == "host_programs")'
  echo "$output" | jq -e 'length == 0'
}

@test "menu_category_rows: Security + Backup carry the structured tool rows" {
  run menu_category_rows Security "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.firewall")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.antivirus")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.rootkit")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.apparmor")'
  run menu_category_rows Backup "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "post_install.backup.zfs_auto_snapshot")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.backup.borg")'
}

# Expert is now a real category (ADR 0071): the ssh + age-key-url remainder.
@test "menu_category_rows: Expert carries ssh + age key url" {
  run menu_category_rows Expert "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.ssh.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.age_key_url")'
  echo "$output" | jq -e 'all(.[]; .section == "Expert")'
}

# the old catch-all "Options" category is gone (its fields were redistributed)
@test "menu_categories: the Options section is gone" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .name != "Options")'
}

# dotfiles_repo is removed entirely — no row in any category (issue 02)
@test "menu_rows: the dotfiles_repo field is gone" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .field != "dotfiles_repo")'
}
