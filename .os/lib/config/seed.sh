#!/usr/bin/env bash
# =============================================================================
# lib/config/seed.sh — Guided Installer default seeder (ADR 0039)
# =============================================================================
# A pure helper over Config State: it fills a launch state with this operator's
# computed defaults so an untouched guided run is ready to install. Independent
# of menu rendering — it writes only Config State, so it survives the menu
# rewrite. Pure: a Config State in, the seeded Config State out, no TTY.
#
# Public API:
#   cfgstate_seed_defaults <state>  → <state> with the launch defaults set
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_set)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# shellcheck source=./post-install.sh
[[ "$(type -t post_install_default)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# cfgstate_seed_defaults <state> — overlay the launch defaults onto <state>.
cfgstate_seed_defaults() {
  local state="$1"
  state="$(cfgstate_set "$state" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" users '["aquastias"]')"
  state="$(cfgstate_set "$state" mode '"single"')"
  state="$(cfgstate_set "$state" system.locale '"en_US.UTF-8"')"
  state="$(cfgstate_set "$state" system.timezone '"Europe/Bucharest"')"
  state="$(cfgstate_set "$state" system.keymap '"us"')"
  # Sysctl Defaults: surface vm.swappiness=10 (the Host Core default) so the
  # guided sysctl screen lists it as the baseline; operator additions ride the
  # override on top. Idempotent with Host Core's own swappiness=10.
  state="$(cfgstate_set "$state" sysctl '{"vm.swappiness":10}')"
  # Selection defaults so no field opens empty and the toggle screens start with
  # a sensible pick: kernel lts, gpu auto, BOTH desktops (this operator's setup),
  # and the default mirror countries. These match the menu display / back-end
  # defaults (kernel/gpu/mirrors are idempotent); desktop is the real choice.
  state="$(cfgstate_set "$state" options.kernel '["lts"]')"
  state="$(cfgstate_set "$state" environment.gpu '"auto"')"
  state="$(cfgstate_set "$state" environment.desktop '["kde","hyprland"]')"
  state="$(cfgstate_set "$state" options.mirror_countries \
    '["Germany","Switzerland","Sweden","France","Romania"]')"
  # zswap Defaults: on by default (zstd, 20% max pool). Rides the baseline so a
  # fresh run shows it with no ● and Save writes it whole, matching the boot
  # layer's accessor defaults. zswap only acts when swap is on (the default).
  state="$(cfgstate_set "$state" options.zswap.enabled 'true')"
  state="$(cfgstate_set "$state" options.zswap.compressor '"zstd"')"
  state="$(cfgstate_set "$state" options.zswap.max_pool_percent '20')"
  # Security & Backup Extras (ADR 0041): pre-tick the secure baseline (firewalld
  # + clamav + rkhunter + apparmor and zfs-auto-snapshot + borg). It rides the
  # baseline layer, so a fresh run shows it with no ● and Save writes it whole.
  state="$(cfgstate_set "$state" post_install "$(post_install_default)")"
  printf '%s\n' "$state"
}
