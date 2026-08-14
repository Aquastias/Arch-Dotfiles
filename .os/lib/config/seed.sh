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
#   cfgstate_seed_defaults <state>  → <state> with the launch defaults set,
#                                     resolved over Host Core
#   cfgstate_host_core              → Host Core as JSON
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_set)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# shellcheck source=./post-install.sh
[[ "$(type -t post_install_default)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# shellcheck source=./layer-resolver.sh
[[ "$(type -t layer_resolve)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/layer-resolver.sh"

# shellcheck source=./layers.sh
[[ "$(type -t _configs_parse)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/layers.sh"

# cfgstate_host_core — Host Core as JSON ({} when absent/unreadable).
# The menu's baseline is LOADED from Host Core rather than hand-copying a few
# of its values (ADR 0058). Hand-copying is why `cups` installed on every host
# and appeared nowhere in the menu, and why packages.repo/aur had no menu
# representation at all.
cfgstate_host_core() {
  local f="${OS_DIR:-}/hosts/core/profile.jsonc"
  [[ -n "${OS_DIR:-}" && -f "$f" ]] || { printf '{}\n'; return 0; }
  _configs_parse "$f" 2>/dev/null || printf '{}\n'
}

# cfgstate_seed_defaults <state> — overlay the launch defaults onto <state>,
# resolved OVER Host Core so everything core installs is visible in the menu.
#
# Host Core is the lower layer and the computed defaults the upper one, folded
# through the Layer Resolver: core's additive contributions (system_programs,
# packages, sysctl, users) survive into the baseline, while the ordered
# selections below (kernel, locale, desktop, mirrors) replace whatever core
# declared. Because these land in the BASELINE and not the override map, they
# render with no ● until the operator actually edits them.
cfgstate_seed_defaults() {
  local state="$1"
  state="$(_cfgstate_computed_defaults "$state")"
  layer_resolve host "$(cfgstate_host_core)" "$state"
}

# _cfgstate_computed_defaults <state> — the guided launch defaults alone,
# without Host Core. Split out so the fold above has a clean upper layer.
_cfgstate_computed_defaults() {
  local state="$1"
  state="$(cfgstate_set "$state" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" users '["aquastias"]')"
  state="$(cfgstate_set "$state" mode '"single"')"
  state="$(cfgstate_set "$state" system.locale '"en_US.UTF-8"')"
  state="$(cfgstate_set "$state" system.timezone '"Europe/Bucharest"')"
  state="$(cfgstate_set "$state" system.keymap '"us"')"
  state="$(cfgstate_set "$state" system.console_font '"default8x16"')"
  # Sysctl is no longer hand-copied here — Host Core is loaded into the
  # baseline, so its swappiness (and everything else it declares) surfaces on
  # its own. Operator additions ride the override on top.
  # Selection defaults so no field opens empty and the toggle screens start with
  # a sensible pick: kernel lts, gpu auto, KDE desktop (the default DE), and the
  # default mirror countries. These match the menu display / back-end defaults
  # (kernel/gpu/mirrors are idempotent); desktop is the real choice.
  state="$(cfgstate_set "$state" options.kernel '["lts"]')"
  state="$(cfgstate_set "$state" environment.gpu '"auto"')"
  state="$(cfgstate_set "$state" environment.display_manager '"auto"')"
  state="$(cfgstate_set "$state" environment.desktop '["kde"]')"
  state="$(cfgstate_set "$state" options.mirror_countries \
    '["Germany","Switzerland","Sweden","France","Romania"]')"
  # Disk / Options scalar defaults (the _MENU_FIELDS spec column): seeding them
  # into the baseline makes it the single default reference the apply-time
  # normalise compares against, so re-picking any shown default clears its ●.
  # All idempotent with Host Core / the accessors (filesystem→zfs, optional
  # repos→[multilib],
  # esp→2G, bootloader→systemd-boot; encryption/impermanence/ssh default off).
  state="$(cfgstate_set "$state" filesystem '"zfs"')"
  # Manual Partitioning kind (ADR 0073): auto = the predefined pool layouts, the
  # untouched default; idempotent with the accessor (disk_config.kind→auto).
  state="$(cfgstate_set "$state" disk_config.kind '"auto"')"
  state="$(cfgstate_set "$state" options.esp_size '"2G"')"
  state="$(cfgstate_set "$state" options.bootloader '"systemd-boot"')"
  state="$(cfgstate_set "$state" options.optional_repos '["multilib"]')"
  state="$(cfgstate_set "$state" options.encryption 'false')"
  state="$(cfgstate_set "$state" options.impermanence.enabled 'false')"
  state="$(cfgstate_set "$state" options.ssh.enabled 'false')"
  # Pacman Options (ADR 0074): the [options] flags shown in the Pacman category.
  # ILoveCandy / Color / VerbosePkgLists on out of the box; the two opt-ins off;
  # ParallelDownloads 5. Rides the baseline (no ● until edited); idempotent with
  # the accessor defaults.
  state="$(cfgstate_set "$state" options.pacman.ilovecandy 'true')"
  state="$(cfgstate_set "$state" options.pacman.color 'true')"
  state="$(cfgstate_set "$state" options.pacman.verbose_pkg_lists 'true')"
  state="$(cfgstate_set "$state" \
    options.pacman.disable_download_timeout 'false')"
  state="$(cfgstate_set "$state" options.pacman.no_progress_bar 'false')"
  state="$(cfgstate_set "$state" options.pacman.parallel_downloads '5')"
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
