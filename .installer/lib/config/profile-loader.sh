#!/usr/bin/env bash
# =============================================================================
# lib/config/profile-loader.sh — Profile Loader, closed-schema validator,
# install-time
#                         disk assembler (ADR 0036)
# =============================================================================
# The pure spine of the unified-profile redesign: read a unified Host (or
# User) Profile and turn it into an effective config, with up-front
# closed-schema validation — no libvirt, no disk writes.
#
# `profile_loader_load <name>` merges hosts/<name>/profile.jsonc over
# hosts/core/profile.jsonc (merge rules per layers.sh) and emits the effective
# config on stdout. profile.jsonc is the *only* host input — there is no
# legacy fallback (issue 10).
#
# Pure: no side effects beyond reading files and writing stdout/stderr.
# Requires INSTALLER_DIR set.
#
# Used by: install.sh, 03-install.sh, tools/explain-packages.sh, the Guided
# Installer, lib/feature-audit/, vm/lib/profile.sh.
# =============================================================================

# shellcheck source=./install-config.sh
declare -F install_config_use_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-config.sh"
# shellcheck source=./layer-resolver.sh
declare -F layer_resolver_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/layer-resolver.sh"
# shellcheck source=./program-registry.sh
declare -F _program_registry_merge >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/program-registry.sh"

# shellcheck source=../picker.sh
declare -F picker_assign_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# shellcheck source=./post-install.sh
declare -F post_install_validate >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# shellcheck source=./printing.sh
declare -F printing_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/printing.sh"
# shellcheck source=./bluetooth.sh
declare -F bluetooth_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/bluetooth.sh"
# shellcheck source=./power.sh
declare -F power_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/power.sh"
# shellcheck source=./mirrors.sh
declare -F mirrors_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/mirrors.sh"

# shellcheck source=../boot/bootloader.sh
declare -F bootloader_is_valid >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/bootloader.sh"

# The Host Profiles that fold the Fleet Layer (ADR 0157): the operator's own
# machines. Every other profile resolves over the neutral Host Core alone.
_PROFILE_LOADER_FLEET_HOSTS=(desktop laptop)

# profile_loader_load <name> — effective host config on stdout.
# profile_loader_load_user <name> — effective user config on stdout (symmetric).
# Both merge <kind>/<name>/profile.jsonc over <kind>/core/profile.jsonc.
# Exit codes: 0 ok | 1 specific missing (core only) | 2 hard error |
#             3 reserved name.
profile_loader_load()      { _profile_loader_load hosts "$1"; }
profile_loader_load_user() { _profile_loader_load users "$1"; }

# Shared loader — merge <kind>/core/profile.jsonc with <kind>/<name>/
# profile.jsonc. VM hosts/users live under <kind>/vm/<name>/ (fallback).
# profile_loader_directory <kind> <name> — a profile's directory: <kind>/<name>,
# else the VM fixture under <kind>/vm/<name>. The one lookup every profile file
# reader (profile.jsonc, secrets.json) shares.
profile_loader_directory() {
  local directory="${INSTALLER_DIR}/$1/$2"
  [[ -d "$directory" ]] || directory="${INSTALLER_DIR}/$1/vm/$2"
  printf '%s\n' "$directory"
}

_profile_loader_load() {
  local kind="$1" name="$2"

  if [[ -z "${INSTALLER_DIR:-}" ]]; then
    echo "profile: INSTALLER_DIR is not set" >&2
    return 2
  fi
  if profile_loader_is_layer "$kind" "$name"; then
    echo "profile: '${name}' is a reserved name (a layer)" >&2
    return 3
  fi

  local core_file="${INSTALLER_DIR}/${kind}/core/profile.jsonc"
  local spec_file
  spec_file="$(profile_loader_directory "$kind" "$name")/profile.jsonc"

  if [[ ! -f "$core_file" ]]; then
    echo "profile: missing ${kind%s} core profile: ${core_file}" >&2
    return 2
  fi
  local core_json
  if ! core_json="$(_program_registry_parse "$core_file")"; then
    echo "profile: failed to parse ${kind%s} core profile: ${core_file}" >&2
    return 2
  fi

  if [[ ! -f "$spec_file" ]]; then
    # Graceful: emit core only, signal via exit code (mirrors the old loader).
    printf '%s\n' "$core_json"
    return 1
  fi

  local spec_json
  if ! spec_json="$(_program_registry_parse "$spec_file")"; then
    echo "profile: failed to parse ${kind%s} profile: ${spec_file}" >&2
    return 2
  fi

  # Resolve through the Layer Resolver (ADR 0057) rather than the blanket concat
  # _program_registry_merge does: with Host Core carrying real content, a core
  # options.kernel of ["lts"] plus a host wanting ["zen"] would otherwise
  # install both. The menu resolves through the same module, so display and
  # install cannot disagree. A fleet host folds the Fleet Layer between the two
  # (ADR 0157).
  local -a layers=("$core_json")
  local fleet_json
  fleet_json="$(_profile_loader_fleet_layer "$kind" "$name")" || return 2
  [[ -n "$fleet_json" ]] && layers+=("$fleet_json")
  layer_resolver_resolve "${kind%s}" "${layers[@]}" "$spec_json"
}

# _profile_loader_fleet_layer <kind> <name> — the Fleet Layer JSON when Host
# Profile <name> folds it, else nothing. A tree with no Fleet Layer file (a test
# fixture) folds nothing. rc 2 when the file does not parse.
_profile_loader_fleet_layer() {
  local fleet_file="${INSTALLER_DIR}/hosts/fleet/profile.jsonc"
  [[ "$1" == hosts && -f "$fleet_file" ]] || return 0
  _profile_loader_folds_fleet "$2" || return 0
  _program_registry_parse "$fleet_file" || {
    echo "profile: failed to parse the Fleet Layer" >&2
    return 2
  }
}

# _profile_loader_folds_fleet <name> — rc 0 when Host Profile <name> folds the
# Fleet Layer.
_profile_loader_folds_fleet() {
  local host
  for host in "${_PROFILE_LOADER_FLEET_HOSTS[@]}"; do
    [[ "$host" == "$1" ]] && return 0
  done
  return 1
}

# profile_loader_is_layer <kind> <name> — rc 0 when <name> is a layer, not a
# profile: `core` for both kinds, plus the Fleet Layer `fleet` for hosts. A
# layer is never loaded, listed or installed on its own.
profile_loader_is_layer() {
  [[ "$2" == core ]] && return 0
  [[ "$1" == hosts && "$2" == fleet ]]
}

# profile_loader_assemble_config <name> <assignment_json> — the install-time
# effective config for `install.sh --profile <name>`. Loads the named profile,
# maps the operator-picked disks onto it (picker_assign_disks), and applies the
# dirname-is-identity hostname fallback (ADR 0036): when the profile omits
# system.hostname, the profile name is used. No host_profile field is emitted.
# Pure: reads files + the JSON arg only, never disks. Exit codes propagate from
# profile_loader_load / picker_assign_disks (min-disk validation aborts here).
profile_loader_assemble_config() {
  local name="$1" assignment="$2" profile_json effective

  profile_json="$(profile_loader_load "$name")" || return $?
  effective="$(picker_assign_disks "$profile_json" "$assignment")" || return $?

  effective="$(profile_loader_default_hostname "$name" "$effective")"
  # Section-derived Host Programs (ADR 0079/0080/0089): fold cups (printing),
  # bluetooth, the power daemon, then reflector (mirrors) into host_programs.
  # Chained so each derives independently and the Runner installs them as
  # authored programs. reflector is state-independent — every install ranks
  # mirrors, so the Mirrors section always brings it.
  mirrors_inject "$(power_inject \
    "$(bluetooth_inject "$(printing_inject "$effective")")")"
}

# profile_loader_default_hostname <name> <config> — <config> with the
# dirname-is-identity hostname fallback (ADR 0036): an absent or empty
# system.hostname becomes the profile name. Shared with the Guided profile
# pick, so both front-ends name the machine alike.
profile_loader_default_hostname() {
  jq --arg name "$1" '
    .system = (.system // {})
    | .system.hostname =
        (if (.system.hostname // "") == "" then $name else .system.hostname end)
  ' <<<"$2"
}

# =============================================================================
# CLOSED-SCHEMA VALIDATION (ADR 0036, amends ADR 0015)
# =============================================================================
# Every authored config is validated against a closed schema at load: any
# unknown key at any depth aborts with its path, before any disk write. The
# schema is expressed as path patterns; a pattern segment is a literal key,
# `*` (any object key — open subtree), or a trailing `[]` (array). The union
# below enumerates every currently-valid key across the host and user
# profile.jsonc; reads (accessors.sh) and these patterns must stay in
# lockstep — a drift guard in the bats suite asserts every
# _INSTALL_CONFIG_SCHEMA read-path is covered here.

_PROFILE_SCHEMA_host=(
  # — system identity (locale/keymap are scalar|array unions — ADR 0036;
  #   console_font is the Locales console-font leaf — ADR 0076) —
  "system.hostname" "system.locale[]" "system.timezone" "system.keymap[]"
  "system.console_font" "system.fullname"
  "dotfiles_repo"
  # — options (kernel is a string|array union — the [] form admits both) —
  "options.kernel[]" "options.bootloader" "options.encryption"
  "options.root_shell"
  "options.swap" "options.swap_size" "options.esp_size" "options.age_key_url"
  "options.zswap.enabled" "options.zswap.compressor"
  "options.zswap.max_pool_percent"
  "options.ssh.enabled" "options.mirror_countries[]"
  # — Printing Service (ADR 0079): the toggle-derived cups switch. Default on;
  #   cups is injected into host_programs at assembly, not declared in core. —
  "options.printing.enabled"
  # — Bluetooth Service (ADR 0080): the toggle-derived bluez switch. Default on;
  #   the `bluetooth` program is injected into host_programs at assembly. —
  "options.bluetooth.enabled"
  # — Power Profile (ADR 0080): the enum-derived power backend (none | ppd |
  #   tuned). The derived daemon program is injected at assembly. —
  "options.power.profile"
  # — Font Catalog (ADR 0080): the curated multi-select of fonts. Absent ⇒ the
  #   catalog defaults; replaces packages.repo.fonts as the single font home. —
  "options.fonts[]"
  # — Mirrors & Repositories (ADR 0072): optional repos (multilib + testing),
  #   custom mirror servers, and archinstall-style custom repositories —
  "options.optional_repos[]" "options.mirror_servers[]"
  "options.custom_repositories[].name" "options.custom_repositories[].url"
  "options.custom_repositories[].sign_check"
  "options.custom_repositories[].sign_option"
  "options.impermanence.enabled" "options.impermanence.dataset"
  "options.impermanence.mount"
  # — Pacman Options (ADR 0074): the [options] block flags surfaced as the
  #   Pacman Configuration Category, applied authoritatively to pacman.conf —
  "options.pacman.ilovecandy" "options.pacman.color"
  "options.pacman.verbose_pkg_lists" "options.pacman.disable_download_timeout"
  "options.pacman.no_progress_bar" "options.pacman.parallel_downloads"
  # — environment (desktop/gpu are string|array unions; display_manager is a
  #   scalar discriminator resolved against the desktop set — ADR 0069;
  #   wayland_shell is the Noctalia work-preset selector — ADR 0090/0097;
  #   stock installs every desktop upstream-stock — ADR 0112) —
  "environment.desktop[]" "environment.gpu[]" "environment.display_manager"
  "environment.wayland_shell" "environment.stock"
  # — layout scalars —
  "ashift" "os_size" "os_pool_name" "storage_pool_name" "storage_mount"
  "mode" "disk"
  # — Filesystem Adapter axis (ADR 0040): discriminator + encryption method —
  "filesystem" "options.encryption_method"
  # — os_pool object (skeleton; disks resolved at install time, disk_count
  #   declares how many the picker/harness assign — ADR 0037) —
  "os_pool.pool_name" "os_pool.ashift" "os_pool.topology" "os_pool.disks[]"
  "os_pool.disk_count"
  # — storage_groups[] (per-group filesystem/encryption — ADR 0043) —
  "storage_groups[].name" "storage_groups[].topology"
  "storage_groups[].mount" "storage_groups[].ashift"
  "storage_groups[].owners[]" "storage_groups[].disks[]"
  "storage_groups[].disk_count"
  "storage_groups[].filesystem" "storage_groups[].encryption"
  # — data_pools[] (per-group filesystem/encryption — ADR 0043) —
  "data_pools[].name" "data_pools[].topology" "data_pools[].mount"
  "data_pools[].ashift" "data_pools[].owners[]" "data_pools[].disks[]"
  "data_pools[].disk_count"
  "data_pools[].filesystem" "data_pools[].encryption"
  # — Manual Partitioning (ADR 0073): the disk-config kind discriminator and
  #   the operator's flat partition assignment. `kind` absent ⇒ auto (today's
  #   pool skeleton above). The partitions[] list is transient (Guided-only,
  #   never committed) but enumerated so an assembled config still validates.
  "disk_config.kind"
  "disk_config.partitions[].device" "disk_config.partitions[].mountpoint"
  "disk_config.partitions[].fs" "disk_config.partitions[].format"
  # — Security & Backup Extras (ADR 0041): structured objects, not bools —
  "post_install.security.firewall" "post_install.security.antivirus"
  "post_install.security.rootkit" "post_install.security.apparmor"
  "post_install.backup.zfs_auto_snapshot" "post_install.backup.borg"
  # — packages (open category objects). `extra` and `groups` were removed:
  #   `extra` was `repo` without a category, `groups` was authored by no
  #   profile and only ever written by the derived GPU/audio buckets, which
  #   are bash arrays and never authorable. Both now abort as unknown keys. —
  "packages.repo.*[]" "packages.aur.*[]"
  # — Layer Resolver control keys (ADR 0056/0057). `exclude` drops something
  #   Host Core declares; `inherit: false` opts out of core's packages ONLY,
  #   so a fixture still inherits core's users and sysctl. —
  "packages.exclude[]" "packages.inherit"
  "host_programs_exclude[]"
  # — host software (config.jsonc) —
  "users[]" "host_programs[]" "sysctl.*"
  "persist.directories[]" "persist.files[]"
)

_PROFILE_SCHEMA_user=(
  "shell" "sudo" "groups[]" "programs[]" "ssh_authorized_keys[]"
  "user_services[]" "git.name" "git.email"
  # — Layer Resolver control key: drop a program User Core declares —
  "programs_exclude[]"
  # — ADR 0134 — start bare (drop User Core's programs wholesale) and skip a
  #   selected program's config while its package still installs —
  "programs_inherit" "config_exclude[]"
)

# `requires[]` (ADR 0065): other Programs whose install-time setup must run
# before this one (e.g. searxng needs podman's package + subuid/subgid). The
# ordering is enforced at validation_check_install_context, before any side
# effect. `conflicts[]` (ADR 0115): other Programs this one is mutually
# exclusive with (e.g. firewalld vs ufw). Symmetric — one side declaring is
# enough. Enforced at validation_check_install_context, before any side effect.
_PROFILE_SCHEMA_program=( "name" "kind" "description" "requires[]" \
  "conflicts[]" "system_services[]" "user_services[]" "stow_opt_in" )

# The closed-schema check: the first (shortest) config path no schema pattern
# admits, rendered dotted ("a.b[].c"); empty when every path is allowed.
# shellcheck disable=SC2016 # a jq program, not shell
_PROFILE_LOADER_SCHEMA_JQ='
  def parse_pat:
    split(".")
    | map(if   . == "*"        then ["*"]
          elif endswith("[]")  then [.[0:length-2], "[]"]
          else [.] end)
    | add;
  def tokmatch($p; $t):
    if   $t == "[]" then ($p|type) == "number"
    elif $t == "*"  then ($p|type) == "string"
    else ($p|type) == "string" and $p == $t end;
  def okprefix($P; $path):
    any($P[];
      . as $t
      | ($path|length) <= ($t|length)
      and all(range(0; $path|length); tokmatch($path[.]; $t[.])));
  def render:
    . as $a
    | reduce range(0; ($a|length)) as $i ("";
        ($a[$i]) as $s
        | if   ($s|type) == "number" then . + "[]"
          elif $i == 0                then ($s|tostring)
          else . + "." + ($s|tostring) end);
  ($pats | split("\n") | map(select(length > 0) | parse_pat)) as $P
  | [ $cfg | paths ]
  | map(select(okprefix($P; .) | not))
  | sort_by(length)
  | if length == 0 then "" else (.[0] | render) end
'

# profile_loader_validate_schema <kind> <json> — kind ∈ {host, user, program}.
# Emits nothing and returns 0 when every key is enumerated; otherwise calls
# error() with the shortest offending path and returns non-zero. Pure: reads
# the JSON arg only, never disks.
profile_loader_validate_schema() {
  local kind="$1" json="$2"
  case "$kind" in
  host | user | program) ;;
  *) error "profile_loader_validate_schema: unknown schema kind '${kind}'"
     return 1 ;;
  esac

  local -n schema_patterns="_PROFILE_SCHEMA_${kind}"
  local patterns
  printf -v patterns '%s\n' "${schema_patterns[@]}"

  local first_unknown_path
  first_unknown_path="$(jq -rn --argjson cfg "$json" --arg pats "$patterns" \
    "$_PROFILE_LOADER_SCHEMA_JQ")" || {
    error "profile_loader_validate_schema: jq failed for ${kind} schema"
    return 1
  }

  if [[ -n "$first_unknown_path" ]]; then
    error "Unknown key '${first_unknown_path}' in ${kind} config" \
          "(closed schema, ADR 0036)." \
          "Fix the typo or remove it before any disk is touched."
    return 1
  fi
}

# _profile_loader_reject_manual <host-json> [<name>] — abort when a committed
# profile declares Manual Partitioning (ADR 0073). It is Guided-Installer-only
# and never committed: a hand-drawn table cannot be replayed from a profile, and
# there is no pool skeleton for the picker to resolve disks against. rc 0
# otherwise. Pure: reads its JSON argument only.
_profile_loader_reject_manual() {
  local json="$1" name="${2:-<profile>}"
  [[ "$(install_config_from_json "$json" disk_kind)" \
     != "manual" ]] && return 0
  error "Profile '${name}' sets disk_config.kind=manual, which is" \
    "Guided-Installer-only (ADR 0073). Remove it, or run the guided installer."
  return 1
}

# _profile_loader_validate_bootloader <host-json> [<name>] — reject an
# options.bootloader value outside the closed set (ADR 0077). The Bootloader
# Manifest's known loaders are pinned to menu_enum_options options.bootloader by
# a drift-guard test, so this rejects a typo with its path before any disk
# write. rc 0 when valid or absent. Pure: reads its JSON argument only.
_profile_loader_validate_bootloader() {
  local json="$1" name="${2:-<profile>}" bootloader
  bootloader="$(printf '%s' "$json" | jq -r '.options.bootloader // empty')"
  [[ -z "$bootloader" ]] && return 0
  bootloader_is_valid "$bootloader" && return 0
  error "Profile '${name}' sets options.bootloader='${bootloader}'," \
    "not one of:" \
    "$(bootloader_all | join_words) (ADR 0077)."
  return 1
}

# profile_loader_validate <name> — the validate-at-load entrypoint. Loads and
# closed-schema-validates the host profile, every referenced user profile,
# and every referenced program config.jsonc (host host_programs + each
# user's programs). Aborts via error() with the offending path on the first
# failure; runs before any disk-touching phase. Requires INSTALLER_DIR set.
profile_loader_validate() {
  local name="$1"

  local host_json
  host_json="$(profile_loader_load "$name")" \
    || { error "profile_loader_validate: cannot load host profile '${name}'"; \
         return 1; }
  profile_loader_validate_schema host "$host_json" || return 1
  _profile_loader_reject_manual "$host_json" "$name" || return 1
  _profile_loader_validate_bootloader "$host_json" "$name" || return 1

  # Security & Backup Extras shape (ADR 0041): reject the old bool form and
  # malformed objects (bad firewall enum, non-bool toggles) — the closed schema
  # only guards key names, not the object/bool distinction at post_install.*.
  local post_install_json
  post_install_json="$(printf '%s' "$host_json" | jq -c '.post_install // {}')"
  post_install_validate "$post_install_json" || return 1

  local -a users
  mapfile -t users < <(printf '%s' "$host_json" | jq -r '.users[]?')

  local user user_json
  for user in "${users[@]}"; do
    [[ -n "$user" ]] || continue
    user_json="$(profile_loader_load_user "$user")" \
      || {
        error "profile_loader_validate: cannot load user profile '${user}'"
        return 1
      }
    profile_loader_validate_schema user "$user_json" || return 1
  done

  program_registry_build

  local -a host_programs user_programs
  mapfile -t host_programs < <(printf '%s' "$host_json" \
    | jq -r '.host_programs[]?')
  _profile_loader_validate_program_configs "${host_programs[@]}" || return 1

  for user in "${users[@]}"; do
    [[ -n "$user" ]] || continue
    user_json="$(profile_loader_load_user "$user")"
    mapfile -t user_programs < <(printf '%s' "$user_json" \
      | jq -r '.programs[]?')
    _profile_loader_validate_program_configs "${user_programs[@]}" || return 1
  done
}

# Closed-schema-validate each named program's config.jsonc. Resolves names
# via the registry; a missing program / config.jsonc / parse error aborts.
_profile_loader_validate_program_configs() {
  local program relative_path config_file json
  for program in "$@"; do
    [[ -n "$program" ]] || continue
    if ! relative_path="$(program_registry_resolve "$program")"; then
      error "profile_loader_validate: program '${program}' not found under" \
            "${INSTALLER_DIR}/programs/<cat>/${program}/"
      return 1
    fi
    config_file="${INSTALLER_DIR}/programs/${relative_path}/config.jsonc"
    if ! json="$(jsonc_strip "$config_file" 2>/dev/null \
                 | jq '.' 2>/dev/null)"; then
      error "profile_loader_validate: program '${program}' config.jsonc" \
            "missing or" \
            "unparseable at ${config_file}"
      return 1
    fi
    profile_loader_validate_schema program "$json" || return 1
  done
}
