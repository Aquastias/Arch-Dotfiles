#!/usr/bin/env bats
# Tests: rows and field placement (split from guided-menu.bats;
# shared setup in guided-menu-helpers.bash)

load guided-menu-helpers


# ── tracer: fresh state lists the hostname row under System, not overridden ──

@test "menu_rows: a fresh state surfaces hostname under System, not overridden" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .section == "System" and .field == "system.hostname")'
  echo "$output" | row system.hostname | jq -e '.overridden == false'
}


# ── a set field shows its value and flips the ● flag ───────────────────────

@test "menu_rows: a set hostname shows its value and is marked overridden" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"

  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row system.hostname | jq -e '.value == "eterniox"'
  echo "$output" | row system.hostname | jq -e '.overridden == true'
}


# ── Disks is filesystem-first; the filesystem defaults to zfs (ADR 0040) ────

@test "menu_rows: the Disks filesystem row defaults to zfs" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row filesystem | jq -e '.section == "Disks"'
  echo "$output" | row filesystem | jq -e '.value == "zfs"'
  echo "$output" | row filesystem | jq -e '.overridden == false'
}


# ── Encryption sits under Disks (the filesystem governs it) ────────────────

@test "menu_rows: the Disks encryption row defaults to false" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.encryption | jq -e '.section == "Disks"'
  echo "$output" | row options.encryption | jq -e '.value == "false"'
  echo "$output" | row options.encryption | jq -e '.overridden == false'
}

@test "menu_rows: an enabled encryption shows true and is overridden" {
  state="$(config_state_set "$(config_state_new)" options.encryption 'true')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.encryption | jq -e '.value == "true"'
  echo "$output" | row options.encryption | jq -e '.overridden == true'
}


# ── Impermanence sits under Disks, offered by default (zfs) ─────────────────

@test "menu_rows: the Disks impermanence row defaults to false" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.impermanence.enabled | jq -e '.section == "Disks"'
  echo "$output" | row options.impermanence.enabled | jq -e '.value == "false"'
}


# ── Impermanence is hidden for non-snapshotting filesystems (ext4 / xfs) ────

@test "menu_rows: the impermanence row is hidden when filesystem is ext4" {
  state="$(config_state_set "$(config_state_new)" filesystem '"ext4"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled") | not'
}

@test "menu_rows: the impermanence row is hidden when filesystem is xfs" {
  state="$(config_state_set "$(config_state_new)" filesystem '"xfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled") | not'
}

@test "menu_rows: the impermanence row is shown for btrfs" {
  state="$(config_state_set "$(config_state_new)" filesystem '"btrfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled")'
}

@test "menu_rows: the impermanence row is shown for zfs (default)" {
  state="$(config_state_set "$(config_state_new)" filesystem '"zfs"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .field == "options.impermanence.enabled")'
}


# ── Options section: FS-agnostic host knobs (issue 05) ─────────────────────

@test "menu_rows: the bootloader row sits under Bootloader, defaults systemd-boot" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.bootloader | jq -e '.section == "Bootloader"'
  echo "$output" | row options.bootloader | jq -e '.value == "systemd-boot"'
  echo "$output" | row options.bootloader | jq -e '.overridden == false'
}


# ── kernel is a token list: defaults lts, renders multi-select comma-joined ─

@test "menu_rows: the kernel row sits under Kernels, defaults lts" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.kernel | jq -e '.section == "Kernels"'
  echo "$output" | row options.kernel | jq -e '.value == "lts"'
}

@test "menu_rows: a multi-kernel selection renders comma-joined, primary first" {
  state="$(config_state_set "$(config_state_new)" options.kernel '["zen","lts"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.kernel | jq -e '.value == "zen, lts"'
  echo "$output" | row options.kernel | jq -e '.overridden == true'
}


# ── the rest of the FS-agnostic knobs surface as rows with their defaults ───
# swap / swap_size / esp_size moved to Disks (issue 02); ssh / age_key_url land
# under Expert (ADR 0071).

@test "menu_rows: storage knobs show under Disks, ssh / age_key_url under Expert" {
  run menu_rows "$(config_state_new)"
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
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.printing.enabled \
    | jq -e '.section == "Daemons"'
  echo "$output" | row options.printing.enabled | jq -e '.value == "true"'
  echo "$output" | row options.printing.enabled | jq -e '.overridden == false'
}

@test "menu_rows: turning printing off shows false and flips ●" {
  state="$(config_state_set "$(config_state_new)" options.printing.enabled 'false')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.printing.enabled | jq -e '.value == "false"'
  echo "$output" | row options.printing.enabled | jq -e '.overridden == true'
}

@test "menu_rows: bluetooth sits under Daemons, defaults true, no ●" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.bluetooth.enabled \
    | jq -e '.section == "Daemons"'
  echo "$output" | row options.bluetooth.enabled | jq -e '.value == "true"'
  echo "$output" | row options.bluetooth.enabled | jq -e '.overridden == false'
}

@test "menu_categories: Daemons is a category with a non-empty summary" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" \
    | jq -e 'any(.[]; .name == "Daemons" and (.summary | length > 0))'
}


# ── Power profile (ADR 0080): an enum leaf, now a Daemons row (ADR 0081) ────

@test "menu_rows: power profile sits under Daemons, defaults ppd, no ●" {
  run menu_rows "$(config_state_new)"
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
  run menu_category_rows "Daemons" "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .section == "Daemons")'
  echo "$output" | jq -e 'any(.[]; .field == "options.printing.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.bluetooth.enabled")'
  echo "$output" | jq -e 'any(.[]; .field == "options.power.profile")'
}

@test "menu_categories: the Daemons ● folds any of its three toggles" {
  run menu_categories "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "Daemons") | .overridden == false'
  state="$(config_state_set "$(config_state_new)" options.bluetooth.enabled 'false')"
  run menu_categories "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.name == "Daemons") | .overridden == true'
}


# ── Environment: desktop (multi) + gpu (auto default) ──────────────────────

@test "menu_rows: the gpu row sits under Environment, defaults auto" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.gpu | jq -e '.section == "Environment"'
  echo "$output" | row environment.gpu | jq -e '.value == "auto"'
}

@test "menu_rows: a multi-gpu selection renders comma-joined under Environment" {
  state="$(config_state_set "$(config_state_new)" environment.gpu '["amd","nvidia"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.gpu | jq -e '.section == "Environment"'
  echo "$output" | row environment.gpu | jq -e '.value == "amd, nvidia"'
  echo "$output" | row environment.gpu | jq -e '.overridden == true'
}

@test "menu_rows: the display_manager row sits under Environment, defaults auto" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.display_manager \
    | jq -e '.section == "Environment"'
  echo "$output" | row environment.display_manager | jq -e '.value == "auto"'
  echo "$output" | row environment.display_manager | jq -e '.overridden == false'
}

@test "menu_rows: a chosen display_manager shows its value and is overridden" {
  state="$(config_state_set "$(config_state_new)" environment.display_manager '"sddm"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row environment.display_manager | jq -e '.value == "sddm"'
  echo "$output" | row environment.display_manager | jq -e '.overridden == true'
}


# ── Options (mirrors) / Packages rows (folded in by issue 02) ──────────────

@test "menu_rows: Mirrors & Repositories carries countries + optional repos + custom" {
  run menu_rows "$(config_state_new)"
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
  state="$(config_state_set "$(config_state_new)" options.custom_repositories \
    '[{"name":"cool","url":"https://x"},{"name":"neat","url":"https://y"}]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row options.custom_repositories | jq -e '.value == "cool, neat"'
}

@test "menu_rows: the extra-packages field row is gone (ADR 0086)" {
  state="$(config_state_set "$(config_state_new)" \
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
  run menu_rows "$(config_state_new)"
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
  baseline="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"

  run menu_rows "$(config_state_new)" "$baseline"        # seed only, no override
  [ "$status" -eq 0 ]
  echo "$output" | row system.hostname | jq -e '.value == "eterniox"'
  echo "$output" | row system.hostname | jq -e '.overridden == false'

  override="$(config_state_set "$(config_state_new)" system.hostname '"myhost"')"
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
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  local baseline; baseline="$(config_state_seed_defaults "$(config_state_new)")"
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
  local rows; rows="$(menu_rows "$(config_state_new)" "$baseline")"
  echo "$rows" | row __language__ | jq -e '.value == "en_US"'
  echo "$rows" | row __encoding__ | jq -e '.value == "UTF-8"'
}


# ── keyboard / locale are Locales rows; timezone is a System row (ADR 0076) ─

@test "menu_rows: keyboard surfaces under Locales, timezone under System" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.keymap   | jq -e '.section == "Locales"'
  echo "$output" | row system.timezone | jq -e '.section == "System"'
}

# the keymap field is labelled `keyboard` under Locales (ADR 0076)
@test "menu_rows: the keymap field is labelled keyboard" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.keymap | jq -e '.label == "keyboard"'
}


# ── locale projection: language + encoding are views of system.locale (0076) ─

@test "menu_rows: fresh state shows language en_US, encoding UTF-8, no ●" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row __language__ | jq -e '.section == "Locales"'
  echo "$output" | row __language__ | jq -e '.value == "en_US" and .overridden == false'
  echo "$output" | row __encoding__ | jq -e '.value == "UTF-8" and .overridden == false'
}

@test "menu_rows: overriding system.locale projects into language + encoding" {
  state="$(config_state_set "$(config_state_new)" system.locale '"de_DE.UTF-8"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  # only the changed part carries ●: language flips, encoding stays UTF-8
  echo "$output" | row __language__ | jq -e '.value == "de_DE" and .overridden == true'
  echo "$output" | row __encoding__ | jq -e '.value == "UTF-8" and .overridden == false'
}

@test "menu_rows: a non-UTF-8 locale marks encoding, not language" {
  state="$(config_state_set "$(config_state_new)" system.locale '"en_US.ISO-8859-1"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row __language__ | jq -e '.value == "en_US" and .overridden == false'
  echo "$output" | row __encoding__ | jq -e '.value == "ISO-8859-1" and .overridden == true'
}

@test "menu_rows: an array locale projects element 0" {
  state="$(config_state_set "$(config_state_new)" system.locale \
    '["fr_FR.UTF-8","en_US.UTF-8"]')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row __language__ | jq -e '.value == "fr_FR"'
}


# ── console font leaf (ADR 0076) ────────────────────────────────────────────

@test "menu_rows: console font is a Locales row defaulting to default8x16" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.console_font | jq -e '.section == "Locales"'
  echo "$output" | row system.console_font \
    | jq -e '.value == "default8x16" and .overridden == false'
}

@test "menu_rows: overriding console font flips its ●" {
  state="$(config_state_set "$(config_state_new)" system.console_font '"ter-116n"')"
  run menu_rows "$state"
  [ "$status" -eq 0 ]
  echo "$output" | row system.console_font \
    | jq -e '.value == "ter-116n" and .overridden == true'
}


# ── the menu still carries a System and a Users section ─────────────────────

@test "menu_rows: the menu carries both a System and a Users section" {
  run menu_rows "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .section == "System")'
  echo "$output" | jq -e 'any(.[]; .section == "Users")'
}

# ── install defaults have one owner: the Install Config schema ──────────────

@test "menu: a field the schema owns declares no default of its own" {
  local paths row path default
  paths="$(printf '%s\n' "${_INSTALL_CONFIG_SCHEMA[@]}" \
    | awk -F'|' '{ sub(/^\./, "", $2); print $2 }')"
  for row in "${_MENU_FIELDS[@]}"; do
    IFS='|' read -r _ path _ default <<<"$row"
    if grep -qx "$path" <<<"$paths" || [[ "$path" == __*__ ]]; then
      [ -z "$default" ] \
        || { echo "menu default for $path: $default"; return 1; }
    fi
  done
}

@test "menu: a schema-owned field shows the schema's install default" {
  local rows
  rows="$(menu_rows '{}' '{}')"
  jq -e '[.[] | select(.field == "options.mirror_countries")][0].value
    == "Germany, Switzerland, Sweden, France, Romania"' <<<"$rows"
  jq -e '[.[] | select(.field == "options.pacman.parallel_downloads")][0].value
    == "5"' <<<"$rows"
  jq -e '[.[] | select(.field == "__language__")][0].value == "en_US"' \
    <<<"$rows"
  jq -e '[.[] | select(.field == "__encoding__")][0].value == "UTF-8"' \
    <<<"$rows"
}
