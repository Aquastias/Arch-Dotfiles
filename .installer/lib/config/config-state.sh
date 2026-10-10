#!/usr/bin/env bash
# =============================================================================
# lib/config/config-state.sh — Guided Installer Config State + seeder
# =============================================================================
# A single in-session Config State: a *sparse override map* over the computed
# defaults (Host Core + accessors). The Guided Installer mutates it through the
# pure verbs below and emits only what the operator changed; the back-end fills
# the rest. The seeder fills a launch state with this operator's computed
# defaults so an untouched guided run is ready to install — independent of menu
# rendering, it writes only Config State (ADR 0039). Pure: in-memory JSON on
# stdin/args → JSON on stdout, no TTY.
#
# Public API:
#   config_state_new                       → fresh (empty) state on stdout
#   config_state_set   <state> <path> <v>  → state with override at <path> = <v>
#   config_state_get   <state> <path>      → raw value at <path> (empty if
#                                            unset)
#   config_state_unset <state> <path>      → state with the override at <path>
#                                            gone
#   config_state_is_overridden <state> <p> → rc 0 if <p> is overridden, else 1
#   config_state_emit  <state>             → the sparse override map (delta)
#   config_state_seed_defaults <state>     → <state> with the launch defaults
#                                            set, resolved over Host Core
#   config_state_host_core                 → Host Core as JSON
#
# <path> is a dotted JSON path ("system.hostname"); <v> is a JSON value
# ('"eterniox"', 'true', '"single"').
#
# Used by: the Guided Installer (lib/guided/*), lib/config/{edits,emit,menu,
# manual-partition}.sh, lib/matrix/assemble.sh.
# =============================================================================

# shellcheck source=./post-install.sh
declare -F post_install_default >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# shellcheck source=./layer-resolver.sh
declare -F layer_resolver_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/layer-resolver.sh"

# shellcheck source=./program-registry.sh
declare -F _program_registry_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/program-registry.sh"

# shellcheck source=./fonts.sh
declare -F fonts_default_selection_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/fonts.sh"

# config_state_new — the initial state: an empty override map.
config_state_new() { printf '%s\n' '{}'; }

# config_state_set <state> <path> <json-value> — record an override at <path>.
config_state_set() {
  local state="$1" path="$2" value="$3"
  jq --arg p "$path" --argjson v "$value" \
    'setpath($p | split("."); $v)' <<<"$state"
}

# config_state_get <state> <path> — the raw value at <path>, empty when unset.
# Only a missing key (null) is empty: a stored `false` is a real value and must
# round-trip ("false"), so this is an explicit null check, not `// empty` (jq's
# // treats false as empty and would swallow a false bool).
config_state_get() {
  local state="$1" path="$2"
  jq -r --arg p "$path" \
    'getpath($p | split(".")) | if . == null then empty else . end' <<<"$state"
}

# config_state_unset <state> <path> — drop the override at <path>. Ancestor
# objects emptied by the deletion are pruned, so a reset field leaves no trace
# in the sparse map (the section disappears when its last override is gone).
config_state_unset() {
  local state="$1" path="$2"
  jq --arg p "$path" '
    delpaths([$p | split(".")])
    | walk(if type == "object" then with_entries(select(.value != {})) else . end)
  ' <<<"$state"
}

# config_state_is_overridden <state> <path> — rc 0 when <path> carries an
# override, rc 1 otherwise. Drives the menu's ● flag.
config_state_is_overridden() {
  local state="$1" path="$2"
  jq -e --arg p "$path" 'getpath($p | split(".")) != null' <<<"$state" >/dev/null
}

# config_state_emit <state> — the sparse override map (a profile delta).
config_state_emit() { jq '.' <<<"$1"; }

# config_state_host_core — Host Core as JSON ({} when absent/unreadable).
# The menu's baseline is LOADED from Host Core rather than hand-copying a few
# of its values (ADR 0058). Hand-copying is why `cups` used to install on every
# host and appear nowhere in the menu (cups is now toggle-derived — ADR 0079),
# and why packages.repo/aur had no menu representation at all.
config_state_host_core() {
  local profile_file="${INSTALLER_DIR:-}/hosts/core/profile.jsonc"
  [[ -n "${INSTALLER_DIR:-}" && -f "$profile_file" ]] \
    || { printf '{}\n'; return 0; }
  _program_registry_parse "$profile_file" 2>/dev/null || printf '{}\n'
}

# config_state_seed_defaults <state> — overlay the launch defaults onto <state>,
# resolved OVER Host Core so everything core installs is visible in the menu.
#
# Host Core is the lower layer and the computed defaults the upper one, folded
# through the Layer Resolver: core's additive contributions (host_programs,
# packages, sysctl, users) survive into the baseline, while the ordered
# selections below (kernel, locale, desktop, mirrors) replace whatever core
# declared. Because these land in the BASELINE and not the override map, they
# render with no ● until the operator actually edits them.
config_state_seed_defaults() {
  local state="$1"
  state="$(_config_state_computed_defaults "$state")"
  layer_resolver_resolve host "$(config_state_host_core)" "$state"
}

# _config_state_computed_defaults <state> — the guided launch defaults alone,
# without Host Core. Split out so the fold above has a clean upper layer.
_config_state_computed_defaults() {
  local state="$1"
  state="$(_config_state_identity_defaults "$state")"
  state="$(_config_state_selection_defaults "$state")"
  state="$(_config_state_disk_defaults "$state")"
  _config_state_service_defaults "$state"
}

# Identity: hostname, the Primary User, layout mode, locale/time/keymap/font.
_config_state_identity_defaults() {
  local state="$1"
  state="$(config_state_set "$state" system.hostname '"eterniox"')"
  state="$(config_state_set "$state" users '["aquastias"]')"
  state="$(config_state_set "$state" mode '"single"')"
  state="$(config_state_set "$state" system.locale '"en_US.UTF-8"')"
  state="$(config_state_set "$state" system.timezone '"Europe/Bucharest"')"
  state="$(config_state_set "$state" system.keymap '"us"')"
  state="$(config_state_set "$state" system.console_font '"default8x16"')"
  printf '%s\n' "$state"
}

_config_state_selection_defaults() {
  local state="$1"
  # Sysctl is no longer hand-copied here — Host Core is loaded into the
  # baseline, so its swappiness (and everything else it declares) surfaces on
  # its own. Operator additions ride the override on top.
  # Selection defaults so no field opens empty and the toggle screens start with
  # a sensible pick: kernel lts, gpu auto, KDE desktop (the default DE), and the
  # default mirror countries. These match the menu display / back-end defaults
  # (kernel/gpu/mirrors are idempotent); desktop is the real choice.
  state="$(config_state_set "$state" options.kernel '["lts"]')"
  state="$(config_state_set "$state" environment.gpu '"auto"')"
  state="$(config_state_set "$state" environment.display_manager '"auto"')"
  state="$(config_state_set "$state" environment.wayland_shell '"noctalia"')"
  # stock (ADR 0112): off by default — the opinionated environment installs.
  state="$(config_state_set "$state" environment.stock 'false')"
  state="$(config_state_set "$state" environment.desktop '["kde"]')"
  state="$(config_state_set "$state" options.mirror_countries \
    '["Germany","Switzerland","Sweden","France","Romania"]')"
  printf '%s\n' "$state"
}

_config_state_disk_defaults() {
  local state="$1"
  # Disk / Options scalar defaults (the _MENU_FIELDS spec column): seeding them
  # into the baseline makes it the single default reference the apply-time
  # normalise compares against, so re-picking any shown default clears its ●.
  # All idempotent with Host Core / the accessors (filesystem→zfs, optional
  # repos→[multilib],
  # esp→auto, bootloader→systemd-boot; encryption/impermanence/ssh off).
  state="$(config_state_set "$state" filesystem '"zfs"')"
  # Manual Partitioning kind (ADR 0073): auto = the predefined pool layouts, the
  # untouched default; idempotent with the accessor (disk_config.kind→auto).
  state="$(config_state_set "$state" disk_config.kind '"auto"')"
  state="$(config_state_set "$state" options.esp_size '"auto"')"
  state="$(config_state_set "$state" options.bootloader '"systemd-boot"')"
  state="$(config_state_set "$state" options.optional_repos '["multilib"]')"
  state="$(config_state_set "$state" options.encryption 'false')"
  state="$(config_state_set "$state" options.impermanence.enabled 'false')"
  state="$(config_state_set "$state" options.ssh.enabled 'false')"
  printf '%s\n' "$state"
}

_config_state_service_defaults() {
  local state="$1"
  # Printing Service (ADR 0079): print daemon on by default; cups is derived at
  # emit, not a baseline host_programs entry. Idempotent with the accessor.
  state="$(config_state_set "$state" options.printing.enabled 'true')"
  # Font Catalog (ADR 0080): seed the default-checked fonts into the baseline so
  # a fresh run shows the default set with no ●. Absent options.fonts resolves
  # to the same set via fonts_selected, so this is idempotent with the back end.
  state="$(config_state_set "$state" options.fonts \
    "$(fonts_default_selection_json)")"
  # Bluetooth Service (ADR 0080): bluez on by default; the bluetooth program is
  # derived at emit, not a baseline entry. Idempotent with the accessor.
  state="$(config_state_set "$state" options.bluetooth.enabled 'true')"
  # Power Profile (ADR 0080): power-profiles-daemon by default; the daemon
  # program is injected at emit. Idempotent with the accessor.
  state="$(config_state_set "$state" options.power.profile \
    '"power-profiles-daemon"')"
  # Pacman Options (ADR 0074): the [options] flags shown in the Pacman category.
  # ILoveCandy / Color / VerbosePkgLists on out of the box; the two opt-ins off;
  # ParallelDownloads 5. Rides the baseline (no ● until edited); idempotent with
  # the accessor defaults.
  state="$(config_state_set "$state" options.pacman.ilovecandy 'true')"
  state="$(config_state_set "$state" options.pacman.color 'true')"
  state="$(config_state_set "$state" options.pacman.verbose_pkg_lists 'true')"
  state="$(config_state_set "$state" \
    options.pacman.disable_download_timeout 'false')"
  state="$(config_state_set "$state" options.pacman.no_progress_bar 'false')"
  state="$(config_state_set "$state" options.pacman.parallel_downloads '5')"
  # zswap Defaults: on by default (zstd, 20% max pool). Rides the baseline so a
  # fresh run shows it with no ● and Save writes it whole, matching the boot
  # layer's accessor defaults. zswap only acts when swap is on (the default).
  state="$(config_state_set "$state" options.zswap.enabled 'true')"
  state="$(config_state_set "$state" options.zswap.compressor '"zstd"')"
  state="$(config_state_set "$state" options.zswap.max_pool_percent '20')"
  # Security & Backup Extras (ADR 0041): pre-tick the secure baseline (firewalld
  # + clamav + rkhunter + apparmor and zfs-auto-snapshot + borg). It rides the
  # baseline layer, so a fresh run shows it with no ● and Save writes it whole.
  state="$(config_state_set "$state" post_install "$(post_install_default)")"
  printf '%s\n' "$state"
}
