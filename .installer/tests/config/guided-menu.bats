#!/usr/bin/env bats
# Tests for .installer/lib/config/menu.sh — the Guided Installer's Menu model
# (ADR
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

# ── tracer: fresh state lists the hostname row under System, not overridden ──

@test "menu_rows: a fresh state surfaces hostname under System, not overridden" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .section == "System" and .field == "system.hostname")'
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
# under Expert (ADR 0071).

@test "menu_rows: storage knobs show under Disks, ssh / age_key_url under Expert" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  # swap / swap_size are no longer menu_rows fields — like layout, they surface
  # as a synthetic controller row (the swap sub-editor) under Disks.
  echo "$output" | jq -e 'all(.[]; .field != "options.swap")'
  echo "$output" | jq -e 'all(.[]; .field != "options.swap_size")'
  echo "$output" | row options.esp_size     | jq -e '.section == "Disks"'
  echo "$output" | row options.esp_size     | jq -e '.value == "auto"'
  echo "$output" | row options.ssh.enabled  | jq -e '.section == "Expert"'
  echo "$output" | row options.ssh.enabled  | jq -e '.value == "false"'
  echo "$output" | row options.age_key_url  | jq -e '.section == "Expert"'
}

# ── Daemons (ADR 0081): printing/bluetooth/power share one category ────────

@test "menu_rows: printing sits under Daemons, defaults true, no ●" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.printing.enabled \
    | jq -e '.section == "Daemons"'
  echo "$output" | row options.printing.enabled | jq -e '.value == "true"'
  echo "$output" | row options.printing.enabled | jq -e '.overridden == false'
}

@test "menu_rows: turning printing off shows false and flips ●" {
  state="$(cfgstate_set "$(cfgstate_new)" options.printing.enabled 'false')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.printing.enabled | jq -e '.value == "false"'
  echo "$output" | row options.printing.enabled | jq -e '.overridden == true'
}

@test "menu_rows: bluetooth sits under Daemons, defaults true, no ●" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.bluetooth.enabled \
    | jq -e '.section == "Daemons"'
  echo "$output" | row options.bluetooth.enabled | jq -e '.value == "true"'
  echo "$output" | row options.bluetooth.enabled | jq -e '.overridden == false'
}

@test "menu_categories: Daemons is a category with a non-empty summary" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .name == "Daemons" and (.summary | length > 0))'
}

# ── Power profile (ADR 0080): an enum leaf, now a Daemons row (ADR 0081) ────

@test "menu_rows: power profile sits under Daemons, defaults ppd, no ●" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.power.profile | jq -e '.section == "Daemons"'
  echo "$output" | row options.power.profile \
    | jq -e '.value == "power-profiles-daemon"'
  echo "$output" | row options.power.profile | jq -e '.overridden == false'
}

@test "menu_enum_options: power profile offers none / ppd / tuned" {
  run menu_enum_options options.power.profile
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx power-profiles-daemon
  echo "$output" | grep -qx tuned
  echo "$output" | grep -qx none
}

@test "menu_category_rows: Daemons returns the three service rows" {
  run menu_category_rows "Daemons" "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "Daemons")'
  echo "$output" | jq -e 'any(.[]; .field == "options.printing.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.bluetooth.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.power.profile")'
}

@test "menu_categories: the Daemons ● folds any of its three toggles" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "Daemons") | .overridden == false'
  state="$(cfgstate_set "$(cfgstate_new)" options.bluetooth.enabled 'false')"
  run menu_categories "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "Daemons") | .overridden == true'
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

@test "menu_rows: the extra-packages field row is gone (ADR 0086)" {
  state="$(cfgstate_set "$(cfgstate_new)" \
    packages.repo.extra '["htop","tmux"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  ! echo "$output" | jq -e 'any(.[]; .field == "packages.repo.extra")'
}

@test "menu_categories: a package edit lights the Packages ● (no field row)" {
  # The Packages ● folds from the package override map, not a field row.
  run menu_categories '{"packages":{"repo":{"extra":["ripgrep"]}}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name=="Packages") | .overridden == true'
  run menu_categories '{"packages":{"exclude":["htop"]}}'      # an exclude too
  echo "$output" | jq -e '.[] | select(.name=="Packages") | .overridden == true'
  run menu_categories '{"packages":{"aur":{"misc":["yay"]}}}'  # aur too
  echo "$output" | jq -e '.[] | select(.name=="Packages") | .overridden == true'
  run menu_categories '{}'                                     # clean → no ●
  echo "$output" | jq -e '.[] | select(.name=="Packages") | .overridden == false'
}

@test "menu_rows: no host programs row (Menu-Owned); post_install split out" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  # host_programs has no menu row (ADR 0086): every host program is Menu-Owned.
  ! echo "$output" | jq -e 'any(.[]; .field == "host_programs")'
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
# baseline value. List/append fields (packages.repo.extra, host_programs
# → "[]") and
# empty defaults are unseeded by design and skipped.

@test "drift: each seeded menu default matches its _MENU_FIELDS spec default" {
  source "$BATS_TEST_DIRNAME/../../lib/config/seed.sh"
  local baseline; baseline="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  local spec section path label default rendered
  for spec in "${_MENU_FIELDS[@]}"; do
    IFS='|' read -r section path label default <<<"$spec"
    [[ -n "$default" && "$default" != "[]" ]] || continue
    # Synthetic projection fields (ADR 0076) have no direct seed path — their
    # default agreement is asserted against the seeded system.locale below.
    [[ "$path" == __*__ ]] && continue
    rendered="$(menu_render_value "$baseline" "$path")"
    [ -n "$rendered" ] \
      || { echo "field $path: spec default '$default' but no baseline seed"; false; }
    [ "$rendered" = "$default" ] \
      || { echo "drift at $path: baseline '$rendered' != spec '$default'"; false; }
  done
  # the seeded system.locale must project to the language/encoding spec defaults
  local rows; rows="$(menu_rows "$(cfgstate_new)" "$baseline")"
  echo "$rows" | row __language__ | jq -e '.value == "en_US"'
  echo "$rows" | row __encoding__ | jq -e '.value == "UTF-8"'
}

# ── keyboard / locale are Locales rows; timezone is a System row (ADR 0076) ─

@test "menu_rows: keyboard surfaces under Locales, timezone under System" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.keymap   | jq -e '.section == "Locales"'
  echo "$output" | row system.timezone | jq -e '.section == "System"'
}

# the keymap field is labelled `keyboard` under Locales (ADR 0076)
@test "menu_rows: the keymap field is labelled keyboard" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.keymap | jq -e '.label == "keyboard"'
}

# ── locale projection: language + encoding are views of system.locale (0076) ─

@test "menu_rows: fresh state shows language en_US, encoding UTF-8, no ●" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row __language__ | jq -e '.section == "Locales"'
  echo "$output" | row __language__ | jq -e '.value == "en_US" and .overridden == false'
  echo "$output" | row __encoding__ | jq -e '.value == "UTF-8" and .overridden == false'
}

@test "menu_rows: overriding system.locale projects into language + encoding" {
  state="$(cfgstate_set "$(cfgstate_new)" system.locale '"de_DE.UTF-8"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  # only the changed part carries ●: language flips, encoding stays UTF-8
  echo "$output" | row __language__ | jq -e '.value == "de_DE" and .overridden == true'
  echo "$output" | row __encoding__ | jq -e '.value == "UTF-8" and .overridden == false'
}

@test "menu_rows: a non-UTF-8 locale marks encoding, not language" {
  state="$(cfgstate_set "$(cfgstate_new)" system.locale '"en_US.ISO-8859-1"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row __language__ | jq -e '.value == "en_US" and .overridden == false'
  echo "$output" | row __encoding__ | jq -e '.value == "ISO-8859-1" and .overridden == true'
}

@test "menu_rows: an array locale projects element 0" {
  state="$(cfgstate_set "$(cfgstate_new)" system.locale \
    '["fr_FR.UTF-8","en_US.UTF-8"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row __language__ | jq -e '.value == "fr_FR"'
}

# ── console font leaf (ADR 0076) ────────────────────────────────────────────

@test "menu_rows: console font is a Locales row defaulting to default8x16" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.console_font | jq -e '.section == "Locales"'
  echo "$output" | row system.console_font \
    | jq -e '.value == "default8x16" and .overridden == false'
}

@test "menu_rows: overriding console font flips its ●" {
  state="$(cfgstate_set "$(cfgstate_new)" system.console_font '"ter-116n"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row system.console_font \
    | jq -e '.value == "ter-116n" and .overridden == true'
}

# ── the menu still carries a System and a Users section ─────────────────────

@test "menu_rows: the menu carries both a System and a Users section" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .section == "System")'
  echo "$output" | jq -e 'any(.[]; .section == "Users")'
}

# ── the two-level model: the fourteen Configuration Categories (ADR 0081) ────
# menu_categories is the top-level contract: the ordered categories the operator
# drills into, in install-flow order under six buckets. Each carries a summary,
# a bucket, and an aggregated ● (any descendant field overridden). The list is
# the same fourteen regardless of state.

cat_at() { jq -e ".[$1]"; }

@test "menu_categories: returns the categories in install-flow order (ADR 0081)" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 14'
  echo "$output" | jq -e '[.[].name] == ["System","Locales","Users","Disks",
    "Bootloader","Kernels","Environment","Mirrors & Repositories","Pacman",
    "Packages","Daemons","Security","Backup","Expert"]'
}

@test "menu_categories: each category carries its bucket" {
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .bucket | length > 0)'
  echo "$output" | jq -e '.[] | select(.name == "System")   | .bucket == "GENERAL"'
  echo "$output" | jq -e '.[] | select(.name == "Daemons") | .bucket == "SERVICES"'
  echo "$output" | jq -e '.[] | select(.name == "Expert") | .bucket == "ADVANCED"'
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
  echo "$output" | jq -e '.[] | select(.name == "System")  | .overridden == true'
  echo "$output" | jq -e '.[] | select(.name == "Disks")   | .overridden == false'
  echo "$output" | jq -e '.[] | select(.name == "Kernels") | .overridden == false'
}

# the ● folds the override map only — a seeded-but-untouched value carries no ●
@test "menu_categories: a baseline-only value leaves the category unmarked" {
  baseline="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  run menu_categories "$(cfgstate_new)" "$baseline"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "System") | .overridden == false'
}

# ── drill-in: menu_category_rows returns one category's field rows ──────────
# The sub-menu contract: given a category name, the rows for that category only
# (same per-row shape as menu_rows). The baseline still supplies seeded values.

@test "menu_category_rows: System returns only System rows incl. hostname" {
  run menu_category_rows System "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "System")'
  echo "$output" | jq -e 'any(.[]; .field == "system.hostname")'
}

# Font Catalog (ADR 0080): the curated multi-select lives as a System leaf.
@test "menu_category_rows: the Font Catalog is a System row" {
  run menu_category_rows System "$(cfgstate_new)"
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
  run menu_categories "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .name == "System" and (.summary | test("fonts")))'
}

# ── menu_top_lines (ADR 0081): the bucketed top-screen category block ────────
@test "menu_top_lines: emits each bucket header once, before its categories" {
  run menu_top_lines "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  # every bucket header present, exactly once
  for b in "── GENERAL ──" "── STORAGE & BOOT ──" "── SOFTWARE ──" \
           "── SERVICES ──" "── SECURITY & DATA ──" "── ADVANCED ──"; do
    [ "$(grep -Fxc "$b" <<<"$output")" -eq 1 ]
  done
  # the GENERAL header leads System, its first category
  printf '%s\n' "$output" | grep -A1 -Fx "── GENERAL ──" | tail -1 \
    | grep -q "^System — "
  # a category line, no header, carries name — summary
  printf '%s\n' "$output" | grep -q "^Daemons — "
}

@test "menu_top_lines: an overridden category carries a trailing ●" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"myhost"')"
  run menu_top_lines "$state"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "^System — .*  ●$"
}

# ADR 0082: a blank spacer line separates one bucket from the next (but not
# before the first bucket header).
@test "menu_top_lines: a blank line separates the buckets" {
  run menu_top_lines "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  # the line immediately before a non-first bucket header is blank
  [ -z "$(printf '%s\n' "$output" | grep -B1 -Fx '── STORAGE & BOOT ──' \
          | head -1)" ]
  # the first line is the first bucket header, not a blank
  [ "$(printf '%s\n' "$output" | head -1)" = "── GENERAL ──" ]
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

# post_install security/backup are their own categories; Packages carries the
# extra-packages row but no host programs row (ADR 0086 — every host program is
# Menu-Owned, so the picker has no members).
@test "menu_category_rows: Packages has no field rows (drill-only)" {
  run menu_category_rows Packages "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  # Neither extra packages nor host programs — Packages is a pure
  # repo/aur/derived drill now (ADR 0086).
  ! echo "$output" | jq -e 'any(.[]; .field == "packages.repo.extra")'
  ! echo "$output" | jq -e 'any(.[]; .field == "host_programs")'
  echo "$output" | jq -e 'length == 0'
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

# Expert is now a real category (ADR 0071): the ssh + age-key-url remainder.
@test "menu_category_rows: Expert carries ssh + age key url" {
  run menu_category_rows Expert "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.ssh.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.age_key_url")'
  echo "$output" | jq -e 'all(.[]; .section == "Expert")'
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
