#!/usr/bin/env bats
# Tests for .os/lib/config/menu.sh — the Guided Installer's Menu model (ADR
# 0039): Config State → menu rows (section / label / value / ● override flag).
# It drives both the fzf shell and these tests, so the rows ARE the contract.
# Pure: JSON-in/JSON-out, no TTY.
#
# Behaviour under test (external only — the rows the model emits), never
# internal structure.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/menu.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
}

row() { jq -e ".[] | select(.field == \"$1\")"; }

# ── tracer: fresh state lists the hostname row under Host, not overridden ───

@test "menu_rows: a fresh state surfaces hostname under General, not overridden" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .section == "General" and .field == "system.hostname")'
  echo "$output" | row system.hostname | jq -e '.overridden == false'
}

# ── a set field shows its value and flips the ● flag ───────────────────────

@test "menu_rows: a set hostname shows its value and is marked overridden" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row system.hostname | jq -e '.value == "eterniox"'
  echo "$output" | row system.hostname | jq -e '.overridden == true'
}

# ── Disks is filesystem-first; the filesystem defaults to zfs (ADR 0040) ────

@test "menu_rows: the Disks filesystem row defaults to zfs" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row filesystem | jq -e '.section == "Disks"'
  echo "$output" | row filesystem | jq -e '.value == "zfs"'
  echo "$output" | row filesystem | jq -e '.overridden == false'
}

# ── Encryption sits under Disks (the filesystem governs it) ────────────────

@test "menu_rows: the Disks encryption row defaults to false" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.encryption | jq -e '.section == "Disks"'
  echo "$output" | row options.encryption | jq -e '.value == "false"'
  echo "$output" | row options.encryption | jq -e '.overridden == false'
}

@test "menu_rows: an enabled encryption shows true and is overridden" {
  state="$(cfgstate_set "$(cfgstate_new)" options.encryption 'true')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.encryption | jq -e '.value == "true"'
  echo "$output" | row options.encryption | jq -e '.overridden == true'
}

# ── Impermanence sits under Disks, offered by default (zfs) ─────────────────

@test "menu_rows: the Disks impermanence row defaults to false" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.impermanence.enabled | jq -e '.section == "Disks"'
  echo "$output" | row options.impermanence.enabled | jq -e '.value == "false"'
}

# ── Impermanence is hidden for non-snapshotting filesystems (ext4 / xfs) ────

@test "menu_rows: the impermanence row is hidden when filesystem is ext4" {
  state="$(cfgstate_set "$(cfgstate_new)" filesystem '"ext4"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled") | not'
}

@test "menu_rows: the impermanence row is hidden when filesystem is xfs" {
  state="$(cfgstate_set "$(cfgstate_new)" filesystem '"xfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled") | not'
}

@test "menu_rows: the impermanence row is shown for btrfs" {
  state="$(cfgstate_set "$(cfgstate_new)" filesystem '"btrfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled")'
}

@test "menu_rows: the impermanence row is shown for zfs (default)" {
  state="$(cfgstate_set "$(cfgstate_new)" filesystem '"zfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled")'
}

# ── Options section: FS-agnostic host knobs (issue 05) ─────────────────────

@test "menu_rows: the bootloader row sits under Bootloader, defaults systemd-boot" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.bootloader | jq -e '.section == "Bootloader"'
  echo "$output" | row options.bootloader | jq -e '.value == "systemd-boot"'
  echo "$output" | row options.bootloader | jq -e '.overridden == false'
}

# ── kernel is a token list: defaults lts, renders multi-select comma-joined ─

@test "menu_rows: the kernel row sits under Kernels, defaults lts" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.kernel | jq -e '.section == "Kernels"'
  echo "$output" | row options.kernel | jq -e '.value == "lts"'
}

@test "menu_rows: a multi-kernel selection renders comma-joined, primary first" {
  state="$(cfgstate_set "$(cfgstate_new)" options.kernel '["zen","lts"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.kernel | jq -e '.value == "zen, lts"'
  echo "$output" | row options.kernel | jq -e '.overridden == true'
}

# ── the rest of the FS-agnostic knobs surface as rows with their defaults ───
# swap / swap_size / esp_size moved to Disks (issue 02); ssh / age_key_url land
# under Advanced (ADR 0071).

@test "menu_rows: storage knobs show under Disks, ssh / age_key_url under Advanced" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  # swap / swap_size are no longer menu_rows fields — like layout, they surface
  # as a synthetic controller row (the swap sub-editor) under Disks.
  echo "$output" | jq -e 'all(.[]; .field != "options.swap")'
  echo "$output" | jq -e 'all(.[]; .field != "options.swap_size")'
  echo "$output" | row options.esp_size     | jq -e '.section == "Disks"'
  echo "$output" | row options.esp_size     | jq -e '.value == "2G"'
  echo "$output" | row options.ssh.enabled  | jq -e '.section == "Advanced"'
  echo "$output" | row options.ssh.enabled  | jq -e '.value == "false"'
  echo "$output" | row options.age_key_url  | jq -e '.section == "Advanced"'
}

# ── Environment: desktop (multi) + gpu (auto default) ──────────────────────

@test "menu_rows: the gpu row sits under Environment, defaults auto" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.gpu | jq -e '.section == "Environment"'
  echo "$output" | row environment.gpu | jq -e '.value == "auto"'
}

@test "menu_rows: a multi-gpu selection renders comma-joined under Environment" {
  state="$(cfgstate_set "$(cfgstate_new)" environment.gpu '["amd","nvidia"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.gpu | jq -e '.section == "Environment"'
  echo "$output" | row environment.gpu | jq -e '.value == "amd, nvidia"'
  echo "$output" | row environment.gpu | jq -e '.overridden == true'
}

@test "menu_rows: the display_manager row sits under Environment, defaults auto" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.display_manager \
    | jq -e '.section == "Environment"'
  echo "$output" | row environment.display_manager | jq -e '.value == "auto"'
  echo "$output" | row environment.display_manager | jq -e '.overridden == false'
}

@test "menu_rows: a chosen display_manager shows its value and is overridden" {
  state="$(cfgstate_set "$(cfgstate_new)" environment.display_manager '"sddm"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.display_manager | jq -e '.value == "sddm"'
  echo "$output" | row environment.display_manager | jq -e '.overridden == true'
}

# ── Options (mirrors) / Packages rows (folded in by issue 02) ──────────────

@test "menu_rows: Mirrors & Repositories carries countries + optional repos + custom" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.mirror_countries \
    | jq -e '.section == "Mirrors & Repositories"'
  echo "$output" | row options.mirror_countries \
    | jq -e '.value == "Germany, Switzerland, Sweden, France, Romania"'
  echo "$output" | row options.optional_repos \
    | jq -e '.section == "Mirrors & Repositories"'
  echo "$output" | row options.optional_repos | jq -e '.value == "multilib"'
  echo "$output" | row options.mirror_servers \
    | jq -e '.section == "Mirrors & Repositories"'
  echo "$output" | row options.custom_repositories \
    | jq -e '.section == "Mirrors & Repositories"'
}

# custom_repositories holds objects — the row value must not error on join, it
# renders the repo names (ADR 0072).
@test "menu_rows: custom_repositories renders repo names, not a jq error" {
  state="$(cfgstate_set "$(cfgstate_new)" options.custom_repositories \
    '[{"name":"cool","url":"https://x"},{"name":"neat","url":"https://y"}]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.custom_repositories | jq -e '.value == "cool, neat"'
}

@test "menu_rows: Packages carries the typed extra-packages row" {
  state="$(cfgstate_set "$(cfgstate_new)" \
    packages.repo.extra '["htop","tmux"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row packages.repo.extra | jq -e '.section == "Packages"'
  echo "$output" | row packages.repo.extra | jq -e '.value == "htop, tmux"'
}

@test "menu_rows: system programs sits under Packages; post_install split out" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system_programs                | jq -e '.section == "Packages"'
  echo "$output" | row post_install.backup.borg       | jq -e '.section == "Backup"'
  echo "$output" | row post_install.security.firewall | jq -e '.section == "Security"'
  echo "$output" | row post_install.security.firewall | jq -e '.value == "firewalld"'
}

# ── baseline layer: a seeded value shows without ●; an override flips it ────
# (issue 01) menu_rows takes an optional baseline (the seed); the row VALUE is
# baseline*override (override wins), but ● reflects the override map only — so a
# fresh, seeded run shows the value with no ● until the operator edits it.

@test "menu_rows: a baseline value shows without ●; an override flips ●" {
  baseline="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run menu_rows "$(cfgstate_new)" "$baseline"        # seed only, no override
  [ "$status" -eq 0 ]
  echo "$output" | row system.hostname | jq -e '.value == "eterniox"'
  echo "$output" | row system.hostname | jq -e '.overridden == false'

  override="$(cfgstate_set "$(cfgstate_new)" system.hostname '"myhost"')"
  run menu_rows "$override" "$baseline"              # operator override wins
  [ "$status" -eq 0 ]
  echo "$output" | row system.hostname | jq -e '.value == "myhost"'
  echo "$output" | row system.hostname | jq -e '.overridden == true'
}

# ── drift guard: the seeded baseline and the _MENU_FIELDS spec agree ──────────
# seed.sh (the baseline) and the _MENU_FIELDS spec-default column are two hand-
# maintained tables. If a default changes in one only, the apply-time normalise
# silently stops clearing ● for that field (the exact bug this fix closes).
# Assert every non-empty, non-list spec default renders equal to its seeded
# baseline value. List/append fields (packages.repo.extra, system_programs
# → "[]") and
# empty defaults are unseeded by design and skipped.

@test "drift: each seeded menu default matches its _MENU_FIELDS spec default" {
  source "$BATS_TEST_DIRNAME/../../lib/config/seed.sh"
  local baseline; baseline="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  local spec section path label default rendered
  for spec in "${_MENU_FIELDS[@]}"; do
    IFS='|' read -r section path label default <<<"$spec"
    [[ -n "$default" && "$default" != "[]" ]] || continue
    rendered="$(menu_render_value "$baseline" "$path")"
    [ -n "$rendered" ] \
      || { echo "field $path: spec default '$default' but no baseline seed"; false; }
    [ "$rendered" = "$default" ] \
      || { echo "drift at $path: baseline '$rendered' != spec '$default'"; false; }
  done
}

# ── keyboard / locale are Locales rows; timezone is a General row (ADR 0076) ─

@test "menu_rows: keyboard surfaces under Locales, timezone under General" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.keymap   | jq -e '.section == "Locales"'
  echo "$output" | row system.timezone | jq -e '.section == "General"'
}

# the keymap field is labelled `keyboard` under Locales (ADR 0076)
@test "menu_rows: the keymap field is labelled keyboard" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.keymap | jq -e '.label == "keyboard"'
}

# ── the menu still carries a General and a Users section ────────────────────

@test "menu_rows: the menu carries both a General and a Users section" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .section == "General")'
  echo "$output" | jq -e 'any(.[]; .section == "Users")'
}

# ── the two-level model: the twelve Configuration Categories (ADR 0071) ─────
# menu_categories is the top-level contract: the ordered categories the operator
# drills into, in archinstall reading order. Each carries a summary and an
# aggregated ● (any descendant field overridden). The list is the same twelve
# regardless of state.

cat_at() { jq -e ".[$1]"; }

@test "menu_categories: returns the categories in canonical order (Pacman after Mirrors)" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 13'
  echo "$output" | jq -e '[.[].name] == ["Locales","Mirrors & Repositories",
    "Pacman","Disks","Bootloader","Kernels","General","Users","Environment",
    "Packages","Security","Backup","Advanced"]'
}

@test "menu_categories: each category carries a non-empty summary" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .summary | length > 0)'
  echo "$output" \
    | jq -e '.[] | select(.name == "Security") | .summary | test("firewall")'
}

@test "menu_categories: a fresh state overrides nothing" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .overridden == false)'
}

@test "menu_categories: editing a field flips only its category's ●" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"myhost"')"
  run menu_categories "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "General") | .overridden == true'
  echo "$output" | jq -e '.[] | select(.name == "Disks")   | .overridden == false'
  echo "$output" | jq -e '.[] | select(.name == "Kernels") | .overridden == false'
}

# the ● folds the override map only — a seeded-but-untouched value carries no ●
@test "menu_categories: a baseline-only value leaves the category unmarked" {
  baseline="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  run menu_categories "$(cfgstate_new)" "$baseline"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "General") | .overridden == false'
}

# ── drill-in: menu_category_rows returns one category's field rows ──────────
# The sub-menu contract: given a category name, the rows for that category only
# (same per-row shape as menu_rows). The baseline still supplies seeded values.

@test "menu_category_rows: General returns only General rows incl. hostname" {
  run menu_category_rows General "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "General")'
  echo "$output" | jq -e 'any(.[]; .field == "system.hostname")'
}

# ── field moves (issue 02): storage knobs surface under Disks ───────────────
# swap / swap_size / esp_size display under Disks (where the operator expects
# storage sizing) while their Config State path stays options.* — the display
# section is independent of the path.

@test "menu_category_rows: esp size surfaces under Disks (swap is synthetic)" {
  run menu_category_rows Disks "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.esp_size")'
  # swap / swap_size moved to the controller's synthetic swap row (sub-editor).
  echo "$output" | jq -e 'all(.[]; .field != "options.swap")'
  echo "$output" | jq -e 'all(.[]; .field != "options.swap_size")'
}

# mirrors + optional repos + custom servers/repos live under Mirrors &
# Repositories (ADR 0071/0072)
@test "menu_category_rows: countries + optional/custom repos under Mirrors & Repositories" {
  run menu_category_rows "Mirrors & Repositories" "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.mirror_countries")'
  echo "$output" | jq -e 'any(.[]; .field == "options.optional_repos")'
  echo "$output" | jq -e 'any(.[]; .field == "options.mirror_servers")'
  echo "$output" | jq -e 'any(.[]; .field == "options.custom_repositories")'
}

# ── Pacman category (ADR 0074): the [options] block flags as a section ───────

@test "menu_categories: Pacman is a category, summary mentions ilovecandy" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .name == "Pacman")'
  echo "$output" \
    | jq -e '.[] | select(.name == "Pacman") | .summary | test("ilovecandy")'
}

@test "menu_category_rows: Pacman carries the six [options] flags with defaults" {
  run menu_category_rows Pacman "$(cfgstate_new)"
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
  state="$(cfgstate_set "$(cfgstate_new)" options.pacman.ilovecandy 'false')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.pacman.ilovecandy | jq -e '.value == "false"'
  echo "$output" | row options.pacman.ilovecandy | jq -e '.overridden == true'
}

@test "menu_categories: editing a Pacman flag flips only the Pacman ●" {
  state="$(cfgstate_set "$(cfgstate_new)" options.pacman.color 'false')"
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
  run menu_category_rows Security "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row sysctl | jq -e '.value == ""'
  echo "$output" | row sysctl | jq -e '.overridden == false'
}

@test "menu_rows: a set sysctl renders key=value pairs and is overridden" {
  state="$(cfgstate_set "$(cfgstate_new)" sysctl '{"vm.swappiness":10}')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row sysctl | jq -e '.value == "vm.swappiness=10"'
  echo "$output" | row sysctl | jq -e '.overridden == true'
}

# the Advanced section dissolves: system programs joins the install lists under
# Packages; post_install security/backup become their own categories.
@test "menu_category_rows: Packages carries extra packages + system programs" {
  run menu_category_rows Packages "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "packages.repo.extra")'
  echo "$output" | jq -e 'any(.[]; .field == "system_programs")'
}

@test "menu_category_rows: Security + Backup carry the structured tool rows" {
  run menu_category_rows Security "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.firewall")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.antivirus")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.rootkit")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.security.apparmor")'
  run menu_category_rows Backup "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "post_install.backup.zfs_auto_snapshot")'
  echo "$output" | jq -e 'any(.[]; .field == "post_install.backup.borg")'
}

# Advanced is now a real category (ADR 0071): the ssh + age-key-url remainder.
@test "menu_category_rows: Advanced carries ssh + age key url" {
  run menu_category_rows Advanced "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.ssh.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.age_key_url")'
  echo "$output" | jq -e 'all(.[]; .section == "Advanced")'
}

# the old catch-all "Options" category is gone (its fields were redistributed)
@test "menu_categories: the Options section is gone" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .name != "Options")'
}

# dotfiles_repo is removed entirely — no row in any category (issue 02)
@test "menu_rows: the dotfiles_repo field is gone" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .field != "dotfiles_repo")'
}
