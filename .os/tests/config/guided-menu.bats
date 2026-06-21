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

@test "menu_rows: a fresh state surfaces hostname under Host, not overridden" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .section == "Host" and .field == "system.hostname")'
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

@test "menu_rows: the impermanence row is shown for btrfs" {
  state="$(cfgstate_set "$(cfgstate_new)" filesystem '"btrfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled")'
}

# ── Options section: FS-agnostic host knobs (issue 05) ─────────────────────

@test "menu_rows: the bootloader row sits under Options, defaults systemd-boot" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.bootloader | jq -e '.section == "Options"'
  echo "$output" | row options.bootloader | jq -e '.value == "systemd-boot"'
  echo "$output" | row options.bootloader | jq -e '.overridden == false'
}

# ── kernel is a token list: defaults lts, renders multi-select comma-joined ─

@test "menu_rows: the kernel row sits under Options, defaults lts" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.kernel | jq -e '.section == "Options"'
  echo "$output" | row options.kernel | jq -e '.value == "lts"'
}

@test "menu_rows: a multi-kernel selection renders comma-joined, primary first" {
  state="$(cfgstate_set "$(cfgstate_new)" options.kernel '["zen","lts"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.kernel | jq -e '.value == "zen, lts"'
  echo "$output" | row options.kernel | jq -e '.overridden == true'
}

# ── the rest of the FS-agnostic Options surface as rows with their defaults ─
# swap / swap_size / esp_size moved to Disks (issue 02); ssh / age_key_url stay.

@test "menu_rows: storage knobs show under Disks, ssh / age_key_url under Options" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.swap         | jq -e '.section == "Disks"'
  echo "$output" | row options.swap         | jq -e '.value == "true"'
  echo "$output" | row options.swap_size    | jq -e '.section == "Disks"'
  # swap_size has no static default — the back-end derives it (RAM×2, capped),
  # and treats empty ≡ "auto"; the row shows "auto" so unset reads legibly.
  echo "$output" | row options.swap_size    | jq -e '.value == "auto"'
  echo "$output" | row options.esp_size     | jq -e '.section == "Disks"'
  echo "$output" | row options.esp_size     | jq -e '.value == "2G"'
  echo "$output" | row options.ssh.enabled  | jq -e '.section == "Options"'
  echo "$output" | row options.ssh.enabled  | jq -e '.value == "false"'
  echo "$output" | row options.age_key_url  | jq -e '.section == "Options"'
}

# ── Environment: desktop (multi) + gpu (auto default) ──────────────────────

@test "menu_rows: the gpu row sits under Environment, defaults auto" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.gpu | jq -e '.section == "Environment"'
  echo "$output" | row environment.gpu | jq -e '.value == "auto"'
}

@test "menu_rows: a multi-desktop selection renders comma-joined under Environment" {
  state="$(cfgstate_set "$(cfgstate_new)" environment.desktop '["kde","hyprland"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.desktop | jq -e '.section == "Environment"'
  echo "$output" | row environment.desktop | jq -e '.value == "kde, hyprland"'
  echo "$output" | row environment.desktop | jq -e '.overridden == true'
}

# ── Options (mirrors) / Packages rows (folded in by issue 02) ──────────────

@test "menu_rows: Options carries mirror_countries (default 5) + multilib" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.mirror_countries | jq -e '.section == "Options"'
  echo "$output" | row options.mirror_countries \
    | jq -e '.value == "Germany, Switzerland, Sweden, France, Romania"'
  echo "$output" | row options.multilib | jq -e '.section == "Options"'
  echo "$output" | row options.multilib | jq -e '.value == "true"'
}

@test "menu_rows: Packages carries the typed extra-packages row" {
  state="$(cfgstate_set "$(cfgstate_new)" packages.extra '["htop","tmux"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row packages.extra | jq -e '.section == "Packages"'
  echo "$output" | row packages.extra | jq -e '.value == "htop, tmux"'
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

# ── locale / timezone / keymap are editable Host rows (issue 01) ───────────

@test "menu_rows: locale / timezone / keymap surface as Host rows" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.locale   | jq -e '.section == "Host"'
  echo "$output" | row system.timezone | jq -e '.section == "Host"'
  echo "$output" | row system.keymap   | jq -e '.section == "Host"'
}

# ── the menu is split Host / Users (mirrors the saved artifacts) ───────────

@test "menu_rows: the menu carries both a Host and a Users section" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .section == "Host")'
  echo "$output" | jq -e 'any(.[]; .section == "Users")'
}

# ── the two-level model: the eight Configuration Categories (issue 02) ──────
# menu_categories is the top-level contract: the ordered categories the operator
# drills into. Each carries a summary and an aggregated ● (any descendant field
# overridden). The category list is the same eight regardless of state.

cat_at() { jq -e ".[$1]"; }

@test "menu_categories: returns the eight categories in canonical order" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 8'
  echo "$output" | jq -e '[.[].name] == ["Host","Disks","Options",
    "Environment","Packages","Security","Backup","Users"]'
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
  echo "$output" | jq -e '.[] | select(.name == "Host")    | .overridden == true'
  echo "$output" | jq -e '.[] | select(.name == "Disks")   | .overridden == false'
  echo "$output" | jq -e '.[] | select(.name == "Options") | .overridden == false'
}

# the ● folds the override map only — a seeded-but-untouched value carries no ●
@test "menu_categories: a baseline-only value leaves the category unmarked" {
  baseline="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  run menu_categories "$(cfgstate_new)" "$baseline"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "Host") | .overridden == false'
}

# ── drill-in: menu_category_rows returns one category's field rows ──────────
# The sub-menu contract: given a category name, the rows for that category only
# (same per-row shape as menu_rows). The baseline still supplies seeded values.

@test "menu_category_rows: Host returns only Host rows incl. hostname" {
  run menu_category_rows Host "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "Host")'
  echo "$output" | jq -e 'any(.[]; .field == "system.hostname")'
}

# ── field moves (issue 02): storage knobs surface under Disks ───────────────
# swap / swap_size / esp_size display under Disks (where the operator expects
# storage sizing) while their Config State path stays options.* — the display
# section is independent of the path.

@test "menu_category_rows: swap / swap size / esp size surface under Disks" {
  run menu_category_rows Disks "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.swap")'
  echo "$output" | jq -e 'any(.[]; .field == "options.swap_size")'
  echo "$output" | jq -e 'any(.[]; .field == "options.esp_size")'
}

# the old Pacman section folds into Options (issue 02)
@test "menu_category_rows: mirror countries + multilib fold into Options" {
  run menu_category_rows Options "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.mirror_countries")'
  echo "$output" | jq -e 'any(.[]; .field == "options.multilib")'
  # the Pacman section no longer exists as a top-level category
  echo "$(menu_categories "$(cfgstate_new)")" \
    | jq -e 'all(.[]; .name != "Pacman")'
}

# sysctl moves off the top-level action list into an Options row; the map value
# renders as comma-joined key=value pairs and flips the Options ● when set.
@test "menu_category_rows: sysctl is an Options row, empty + unmarked when unset" {
  run menu_category_rows Options "$(cfgstate_new)"
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
  echo "$output" | jq -e 'any(.[]; .field == "packages.extra")'
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

@test "menu_categories: the Advanced section is gone" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .name != "Advanced")'
}

# dotfiles_repo is removed entirely — no row in any category (issue 02)
@test "menu_rows: the dotfiles_repo field is gone" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .field != "dotfiles_repo")'
}
