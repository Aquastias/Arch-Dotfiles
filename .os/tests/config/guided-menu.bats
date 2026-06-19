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

@test "menu_rows: swap / swap_size / esp_size / ssh / age_key_url under Options" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row options.swap         | jq -e '.section == "Options"'
  echo "$output" | row options.swap         | jq -e '.value == "true"'
  echo "$output" | row options.swap_size    | jq -e '.section == "Options"'
  # swap_size has no static default — the back-end derives it (RAM×2, capped),
  # and treats empty ≡ "auto"; the row shows "auto" so unset reads legibly.
  echo "$output" | row options.swap_size    | jq -e '.value == "auto"'
  echo "$output" | row options.esp_size     | jq -e '.value == "2G"'
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

# ── the menu is split Host / Users (mirrors the saved artifacts) ───────────

@test "menu_rows: the menu carries both a Host and a Users section" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .section == "Host")'
  echo "$output" | jq -e 'any(.[]; .section == "Users")'
}
