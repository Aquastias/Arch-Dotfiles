#!/usr/bin/env bash
# =============================================================================
# lib/config/install-config.sh — Install Config Reader (typed accessors)
# =============================================================================
# Sole owner of Install Config schema defaults. The schema below is the
# canonical declaration of every regular Install Config field: jq path, type
# and default value. The `install_config_<name>` wrappers are generated from
# this schema at source time and forward to `install_config_get`.
#
# To find where a regular accessor is defined, grep this file for the schema
# row — that is the declaration site. The hand-written specials below the
# schema (notably Kernel Selection) each break the schema mould.
#
# Per-group accessors live in install-config-groups.sh (sourced at the end).
#
# Requires lib/common.sh (jsonc_read, error) already sourced.
#
# Used by: 01-bootstrap-zfs.sh, 03-install.sh, lib/feature-audit/manifest.sh,
# and every install-time lib reading the Install Config.
# =============================================================================

# shellcheck source=../common.sh
declare -F jsonc_read >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"

# shellcheck source=../packages/kernel.sh
declare -F kernel_is_valid_token >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/kernel.sh"

# Schema rows: name|jq_path|type|default — the one owner of Install Defaults;
# menu and seed derive theirs from it, launch presets stay in the seed
# (ADR 0154). Type ∈ {scalar, number, bool, array}; number seeds as a JSON
# number, an array default lists its elements by comma, empty = none.
# shellcheck disable=SC2140 # a long row is two adjacent strings (80 columns)
_INSTALL_CONFIG_SCHEMA=(
  "bootloader|.options.bootloader|scalar|systemd-boot"
  "swap_enabled|.options.swap|bool|true"
  "zswap_enabled|.options.zswap.enabled|bool|true"
  "zswap_compressor|.options.zswap.compressor|scalar|zstd"
  "zswap_max_pool_percent|.options.zswap.max_pool_percent|number|20"
  # ZFS ARC cap (ADR 0161): profile-only, empty = the ZFS default. Validated by
  # zfs_arc_max_bytes; emitted as a kernel parameter (lib/boot/zfs-arc.sh).
  "zfs_arc_max|.options.zfs.arc_max|scalar|"
  "esp_size|.options.esp_size|scalar|auto"
  "root_shell|.options.root_shell|scalar|/bin/bash"
  "ssh_enabled|.options.ssh.enabled|bool|false"
  # Printing Service (ADR 0079): the toggle-derived print-daemon switch, default
  # on. cups is injected into host_programs from this at assembly; this is the
  # typed back-end reader (printing_enabled in printing.sh reads the raw config
  # for the pure injector/resolver).
  "printing_enabled|.options.printing.enabled|bool|true"
  # Bluetooth Service (ADR 0080): the toggle-derived bluez switch, default on.
  # The `bluetooth` program is injected into host_programs from this at
  # assembly; bluetooth_enabled in bluetooth.sh reads the raw config for the
  # pure injector/resolver.
  "bluetooth_enabled|.options.bluetooth.enabled|bool|true"
  # Power Profile (ADR 0080): the enum-derived power-management backend, default
  # power-profiles-daemon. The value maps to a Host Program (ppd/tuned)
  # injected into host_programs at assembly; none installs nothing.
  "power_profile|.options.power.profile|scalar|power-profiles-daemon"
  "impermanence_enabled|.options.impermanence.enabled|bool|false"
  "impermanence_dataset|.options.impermanence.dataset|scalar|rpool/persist"
  "impermanence_mount|.options.impermanence.mount|scalar|/persist"
  "age_key_url|.options.age_key_url|scalar|"
  "hostname|.system.hostname|scalar|"
  # timezone is NOT a schema row: it is resolved, not read raw (ADR 0118), so it
  # is a hand-written special below (it breaks the pure-default mould, like the
  # array/kernel specials).
  # Primary User display name → GECOS via useradd -c (ADR 0121). Default "Alex"
  # (the operator's), applied to the Primary User only by the Runner; an
  # explicit value overrides. Not a per-user schema — that is out of scope.
  "fullname|.system.fullname|scalar|Alex"
  # Console font (ADR 0076) — the Locales console-font leaf, written as FONT= in
  # /etc/vconsole.conf. default8x16 is always present (kbd ∈ base).
  "console_font|.system.console_font|scalar|default8x16"
  "desktop|.environment.desktop|array|"
  "display_manager|.environment.display_manager|scalar|auto"
  "wayland_shell|.environment.wayland_shell|scalar|noctalia"
  "dotfiles_repo|.dotfiles_repo|scalar|"
  "os_pool_name|.os_pool_name|scalar|rpool"
  "storage_pool_name|.storage_pool_name|scalar|dpool"
  "storage_mount|.storage_mount|scalar|/data"
  "ashift|.ashift|number|12"
  "os_pool_ashift|.os_pool.ashift|number|13"
  "encryption_enabled|.options.encryption|bool|false"
  "filesystem|.filesystem|scalar|zfs"
  # Manual Partitioning (ADR 0073): the disk-config kind discriminator. Absent
  # ⇒ auto (today's pool skeleton); manual selects the flat partitions[] path.
  "disk_kind|.disk_config.kind|scalar|auto"
  # Pacman Options (ADR 0074): the pacman [options] block flags the Pacman
  # Configuration Category surfaces. Applied authoritatively to the host
  # /etc/pacman.conf before pacstrap; CheckSpace is deliberately absent (the ZFS
  # path force-disables it) and multilib stays under Optional Repositories.
  "pacman_ilovecandy|.options.pacman.ilovecandy|bool|true"
  "pacman_color|.options.pacman.color|bool|true"
  "pacman_verbose_pkg_lists|.options.pacman.verbose_pkg_lists|bool|true"
  "pacman_disable_download_timeout|"\
".options.pacman.disable_download_timeout|bool|false"
  "pacman_no_progress_bar|.options.pacman.no_progress_bar|bool|false"
  "pacman_parallel_downloads|.options.pacman.parallel_downloads|number|5"
  "swap_size|.options.swap_size|scalar|auto"
  "stock|.environment.stock|bool|true"
  "gpu|.environment.gpu|array|auto"
  "locales|.system.locale|array|en_US.UTF-8"
  "keymaps|.system.keymap|array|us"
  # Empty: reflector ranks every mirror worldwide (ADR 0157); the Fleet Layer
  # pins the operator's countries.
  "mirror_countries|.options.mirror_countries|array|"
  "optional_repos|.options.optional_repos|array|multilib"
  "kernels|.options.kernel|array|lts"
)

# The schema rows split once, at source time: each name's jq path, type and
# install default ("" = none), and the names in schema order.
declare -gA _INSTALL_CONFIG_PATHS=() _INSTALL_CONFIG_TYPES=()
declare -gA _INSTALL_CONFIG_DEFAULTS=()
declare -ga _INSTALL_CONFIG_NAMES=()
while IFS='|' read -r _name _path _type _default; do
  _INSTALL_CONFIG_PATHS[$_name]="$_path"
  _INSTALL_CONFIG_TYPES[$_name]="$_type"
  _INSTALL_CONFIG_DEFAULTS[$_name]="$_default"
  _INSTALL_CONFIG_NAMES+=("$_name")
done < <(printf '%s\n' "${_INSTALL_CONFIG_SCHEMA[@]}")
unset _name _path _type _default

# Accessors read CONFIG_FILE, or a bound JSON config (ADR 0154). Binding is
# process state, so JSON holders read through install_config_from_json.
_INSTALL_CONFIG_BOUND=false
_INSTALL_CONFIG_JSON=""

# install_config_use_json <json> — read <json> from now on (empty = `{}`).
install_config_use_json() {
  _INSTALL_CONFIG_BOUND=true
  _INSTALL_CONFIG_JSON="${1:-{\}}"
}

# install_config_use_file — read CONFIG_FILE again.
install_config_use_file() { _INSTALL_CONFIG_BOUND=false; }

# install_config_from_json <json> <accessor> [args…] — one accessor (the name
# after `install_config_`) over <json>, bound in a subshell that cannot leak.
install_config_from_json() {
  local json="$1" accessor="$2"; shift 2
  (install_config_use_json "$json"; "install_config_$accessor" "$@")
}

# _install_config_read <jq-filter> — the filter over the Effective Config, raw.
_install_config_read() {
  if [[ "$_INSTALL_CONFIG_BOUND" == true ]]; then
    # The filter over the bound JSON.
    printf '%s\n' "$_INSTALL_CONFIG_JSON" | jq -r "$1"
  else jsonc_read "$CONFIG_FILE" "$1"; fi
}

# _install_config_optional <path> — the field, or empty when missing / null.
_install_config_optional() { _install_config_read "$1 // empty"; }

# _install_config_row <name> — rc 0 for a schema name; an unknown name is an
# error.
_install_config_row() {
  [[ -n "$1" && -n "${_INSTALL_CONFIG_TYPES[$1]:-}" ]] && return 0
  error "install_config: unknown schema name '$1'"
}

# install_config_default <name> — the install default: what the field means
# when absent. Arrays emit one element per line (the row lists them by comma).
install_config_default() {
  local default_value
  _install_config_row "$1" || return 1
  default_value="${_INSTALL_CONFIG_DEFAULTS[$1]}"
  [[ -n "$default_value" ]] || return 0
  printf '%s\n' "$default_value" | tr ',' '\n'
}

# install_config_default_object <name>... — the named install defaults as one
# typed JSON object at their paths (bool / number as JSON, arrays as arrays),
# for the guided seed and menu. A field with no install default is left out.
# One jq call: each default is an --arg, set at its path.
install_config_default_object() {
  local name value expression index=0 program='{}'
  local -a arguments=()
  for name in "$@"; do
    _install_config_row "$name" || return 1
    value="${_INSTALL_CONFIG_DEFAULTS[$name]}"
    [[ -n "$value" ]] || continue
    case "${_INSTALL_CONFIG_TYPES[$name]}" in
    bool | number) expression="(\$v${index} | fromjson)" ;;
    array) expression="(\$v${index} | split(\",\"))" ;;
    *) expression="\$v${index}" ;;
    esac
    program+=" | ${_INSTALL_CONFIG_PATHS[$name]} = ${expression}"
    arguments+=(--arg "v${index}" "$value")
    index=$((index + 1))
  done
  # The defaults, each at its path.
  jq -n "${arguments[@]}" "$program"
}

# install_config_schema_names — every schema row's name, one per line.
install_config_schema_names() {
  printf '%s\n' "${_INSTALL_CONFIG_NAMES[@]}"
}

# install_config_get <name> — schema dispatcher for the accessors below.
# Reads the named field according to its schema row and applies the default.
install_config_get() {
  local jq_path value
  _install_config_row "$1" || return 1
  jq_path="${_INSTALL_CONFIG_PATHS[$1]}"
  case "${_INSTALL_CONFIG_TYPES[$1]}" in
  scalar | number) value="$(_install_config_optional "$jq_path")" ;;
  bool)
    value="$(_install_config_read "$jq_path")"
    [[ "$value" == "null" ]] && value=""
    ;;
  array) value="$(_install_config_array "$jq_path")" ;;
  esac
  if [[ -n "$value" ]]; then printf '%s\n' "$value"
  else install_config_default "$1"; fi
}

# One accessor per schema row, reading it through install_config_get. The
# rows with extra logic (impermanence_enabled, encryption_enabled,
# optional_repos, kernels) have their own definitions below.
install_config_bootloader() { install_config_get bootloader; }
install_config_swap_enabled() { install_config_get swap_enabled; }
install_config_zswap_enabled() { install_config_get zswap_enabled; }
install_config_zswap_compressor() { install_config_get zswap_compressor; }
install_config_zswap_max_pool_percent() {
  install_config_get zswap_max_pool_percent
}
install_config_zfs_arc_max() { install_config_get zfs_arc_max; }
install_config_esp_size() { install_config_get esp_size; }
install_config_root_shell() { install_config_get root_shell; }
install_config_ssh_enabled() { install_config_get ssh_enabled; }
install_config_printing_enabled() { install_config_get printing_enabled; }
install_config_bluetooth_enabled() { install_config_get bluetooth_enabled; }
install_config_power_profile() { install_config_get power_profile; }
install_config_impermanence_dataset() {
  install_config_get impermanence_dataset
}
install_config_impermanence_mount() { install_config_get impermanence_mount; }
install_config_age_key_url() { install_config_get age_key_url; }
install_config_hostname() { install_config_get hostname; }
install_config_fullname() { install_config_get fullname; }
install_config_console_font() { install_config_get console_font; }
install_config_desktop() { install_config_get desktop; }
install_config_display_manager() { install_config_get display_manager; }
install_config_wayland_shell() { install_config_get wayland_shell; }
install_config_dotfiles_repo() { install_config_get dotfiles_repo; }
install_config_os_pool_name() { install_config_get os_pool_name; }
install_config_storage_pool_name() { install_config_get storage_pool_name; }
install_config_storage_mount() { install_config_get storage_mount; }
install_config_ashift() { install_config_get ashift; }
install_config_os_pool_ashift() { install_config_get os_pool_ashift; }
install_config_filesystem() { install_config_get filesystem; }
install_config_disk_kind() { install_config_get disk_kind; }
install_config_pacman_ilovecandy() { install_config_get pacman_ilovecandy; }
install_config_pacman_color() { install_config_get pacman_color; }
install_config_pacman_verbose_pkg_lists() {  # readability-ok: frozen key
  install_config_get pacman_verbose_pkg_lists
}
install_config_pacman_disable_download_timeout() {
  install_config_get pacman_disable_download_timeout
}
install_config_pacman_no_progress_bar() {
  install_config_get pacman_no_progress_bar
}
install_config_pacman_parallel_downloads() {
  install_config_get pacman_parallel_downloads
}
install_config_swap_size() { install_config_get swap_size; }
install_config_stock() { install_config_get stock; }
install_config_gpu() { install_config_get gpu; }
install_config_locales() { install_config_get locales; }
install_config_keymaps() { install_config_get keymaps; }
install_config_mirror_countries() { install_config_get mirror_countries; }

# Manual Partitioning neutralises the pool-dependent options (ADR 0073). A plain
# hand-partitioned layout has no ZFS dataset to roll back and no pool to
# encrypt, so impermanence and encryption read false under kind=manual whatever
# override the (shown-but-locked) menu row still carries — the back-end must
# never act on a stale value the operator cannot edit.
install_config_impermanence_enabled() {
  [[ "$(install_config_disk_kind)" == "manual" ]] \
    && { printf 'false\n'; return; }
  install_config_get impermanence_enabled
}
install_config_encryption_enabled() {
  [[ "$(install_config_disk_kind)" == "manual" ]] \
    && { printf 'false\n'; return; }
  install_config_get encryption_enabled
}

# AppArmor is selected iff the resolved Security & Backup Extras (ADR 0041)
# hold it — the same rule that installs the program — so the LSM cmdline
# (lib/boot/lsm.sh) and the package always agree. Absent / legacy = off.
install_config_apparmor_enabled() {
  declare -F post_install_programs >/dev/null 2>&1 \
    || source "${BASH_SOURCE[0]%/*}/post-install.sh"
  if post_install_programs \
       "$(_install_config_read '.post_install // {} | tojson')" \
     | grep -qx apparmor; then
    printf 'true\n'
  else printf 'false\n'; fi
}

# Timezone is resolved, not read raw (ADR 0118): an explicit/guided value wins,
# else geo-IP autodetect, else UTC. A hand-written special (no
# schema row) because it breaks the pure-default mould. The Timezone resolver is
# sourced by 03-install before the single persist call site; tests that stub
# install_config_timezone override this (last definition wins).
install_config_timezone() {
  timezone_resolve "$(_install_config_optional .)"
}

# =============================================================================
# Hand-written specials — kept verbatim because each breaks the schema mould.
# =============================================================================

# Array reader: accepts string ("kde"), array (["kde"]), or
# null/absent. Emits one line per element; zero lines when absent/null.
_install_config_array() {
  _install_config_read "$1 | if type == \"array\" then .[]
    elif type == \"string\" then . else empty end"
}

# Encryption method (ADR 0040) — scalar with a filesystem-derived default. The
# enablement bool (install_config_encryption_enabled) is untouched; this only
# names the cipher seam: ZFS uses native AES, every other filesystem uses LUKS.
# An explicit options.encryption_method wins.
install_config_encryption_method() {
  local value; value="$(_install_config_optional '.options.encryption_method')"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  elif [[ "$(install_config_filesystem)" == "zfs" ]]; then
    printf '%s\n' "native"
  else
    printf '%s\n' "luks"
  fi
}

# Locale / Keymap Selection (ADR 0036) — scalar|array union. Element 0 is the
# default (LANG / console KEYMAP); the rest are generated locales / available
# desktop layouts. The *s accessors are array schema rows (one token per line,
# primary first); the singular ones return the primary for scalar consumers.
install_config_locale() {
  install_config_locales | head -n 1
}

install_config_keymap() {
  install_config_keymaps | head -n 1
}

# Optional Repositories (ADR 0072) — the pacman repos enabled beyond core/extra:
# any of `multilib`, `multilib-testing`, `core-testing`, `extra-testing`. Emits
# one repo per line. Defaults to `multilib` when the key is absent, preserving
# the historical `options.multilib=true` default; an explicit empty array (`[]`)
# means "no optional repos" and is honoured (multilib off).
install_config_optional_repos() {
  local raw; raw="$(_install_config_read '.options.optional_repos')"
  if [[ "$raw" == "null" ]]; then
    install_config_default optional_repos
  else
    _install_config_array '.options.optional_repos'
  fi
}

# install_config_multilib — back-compat shim: "true" iff `multilib` is among the
# Optional Repositories, so the historical bool read-site keeps working.
install_config_multilib() {
  install_config_optional_repos | grep -qx multilib && echo true || echo false
}

# Custom mirror servers (ADR 0072) — operator-supplied `Server = <url>` lines
# prepended to the reflector-built mirrorlist. One URL per line, order
# preserved, empty when unset.
install_config_mirror_servers() {
  _install_config_array '.options.mirror_servers'
}

# Custom repositories (ADR 0072) — archinstall-style extra pacman repos. Emits
# one repo per line as TSV `name<TAB>url<TAB>sign_check<TAB>sign_option`
# (sign_check ∈ Never|Optional|Required, sign_option ∈ TrustAll|TrustedOnly;
# both default to the pacman-standard Required/TrustedOnly when omitted). Empty
# when none are declared.
install_config_custom_repositories() {
  local rows='(. // [])[] | [.name, .url, (.sign_check // "Required"),'
  rows+=' (.sign_option // "TrustedOnly")] | @tsv'
  # One TSV row per declared repository.
  _install_config_read '.options.custom_repositories' 2>/dev/null \
    | jq -r "$rows" 2>/dev/null
}

# install_config_persist_json — the effective config's Persist Extensions as
# {directories, files} JSON (each defaulting to []).
install_config_persist_json() {
  _install_config_read '{directories: (.persist.directories // []),
    files: (.persist.files // [])}'
}

# Kernel Selection — accepts a single flavour token (string) or a list. Emits
# one token per line, ordered, primary (first selected) first. Defaults to
# 'lts' when absent or null. Aborts on any unknown flavour token, so a typo
# cannot silently install the wrong or no kernel.
install_config_kernels() {
  local out token
  out="$(install_config_get kernels)"
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    kernel_is_valid_token "$token" || {
      error "Unknown kernel token in options.kernel: '$token'.
  Valid tokens: $(kernel_valid_tokens). See ADR 0024."
      return 1
    }
  done < <(printf '%s\n' "$out")
  printf '%s\n' "$out"
}

# Primary Kernel — the first selected token. Back-compat scalar accessor for
# consumers (initramfs preset, bootloader default) that understand one kernel.
install_config_kernel() {
  install_config_kernels | head -n 1
}

# The wlroots compositors: the desktops the Wayland Shell Companion layers on
# (ADR 0097). The one owner of the set; every "is it wlroots?" asks here.
_INSTALL_CONFIG_WLROOTS_DESKTOPS=(hyprland niri umbriel)

# install_config_is_wlroots_desktop <desktop> — rc 0 for a wlroots compositor.
install_config_is_wlroots_desktop() {
  local desktop
  for desktop in "${_INSTALL_CONFIG_WLROOTS_DESKTOPS[@]}"; do
    [[ "$1" == "$desktop" ]] && return 0
  done
  return 1
}

# shellcheck source=./install-config-groups.sh
source "${BASH_SOURCE[0]%/*}/install-config-groups.sh"
