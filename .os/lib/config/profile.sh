#!/usr/bin/env bash
# =============================================================================
# lib/config/profile.sh — Profile Loader, closed-schema validator, transient
#                         migration assembler (ADR 0036)
# =============================================================================
# The pure spine of the unified-profile redesign: read a unified Host (or
# User) Profile and turn it into an effective config, with up-front
# closed-schema validation — no libvirt, no disk writes.
#
# `load_profile <name>` returns the effective config on stdout:
#   - When hosts/<name>/profile.jsonc exists, merges it over
#     hosts/core/profile.jsonc (merge rules per layers.sh).
#   - Otherwise (transient migration scaffold) it synthesizes the same
#     effective config from the legacy install.template.jsonc + config.jsonc
#     through the existing picker assembler, so callers read "a profile"
#     before the files are migrated. Removed with the legacy readers at the
#     end of the migration.
#
# Pure: no side effects beyond reading files and writing stdout/stderr.
# Requires OS_DIR set.
# =============================================================================

# shellcheck source=./layers.sh
[[ "$(type -t _configs_merge)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/layers.sh"

# shellcheck source=../picker.sh
[[ "$(type -t picker_load_template)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# load_profile <name> — effective host config on stdout.
# Prefers a real hosts/<name>/profile.jsonc (merged over core); when absent,
# falls back to the transient scaffold that synthesizes the same shape from
# the legacy template + config.
# Exit codes mirror load_host_config: 0 ok | 2 hard error | 3 reserved name.
load_profile() {
  local name="$1"

  if [[ -z "${OS_DIR:-}" ]]; then
    echo "profile: OS_DIR is not set" >&2
    return 2
  fi
  if [[ "$name" == "core" ]]; then
    echo "profile: 'core' is a reserved name and cannot be loaded" >&2
    return 3
  fi

  if [[ -f "${OS_DIR}/hosts/${name}/profile.jsonc" ]]; then
    _profile_real_merge hosts "$name"
  else
    _load_profile_synthesize "$name"
  fi
}

# Real path — merge <kind>/<name>/profile.jsonc over <kind>/core/profile.jsonc
# (merge rules per layers.sh). <kind> is `hosts` or `users`.
_profile_real_merge() {
  local kind="$1" name="$2"
  local core_file="${OS_DIR}/${kind}/core/profile.jsonc"
  local spec_file="${OS_DIR}/${kind}/${name}/profile.jsonc"

  local core_json spec_json
  core_json="$(_configs_parse "$core_file" 2>/dev/null)" || core_json='{}'
  if ! spec_json="$(_configs_parse "$spec_file")"; then
    echo "profile: failed to parse ${kind%s} profile: ${spec_file}" >&2
    return 2
  fi

  _configs_merge "$core_json" "$spec_json"
}

# load_user_profile <name> — effective user config on stdout. Symmetric with
# load_profile; the user side has no install template, so the transient
# scaffold synthesizes from the legacy user config.jsonc alone.
load_user_profile() {
  local name="$1"

  if [[ -z "${OS_DIR:-}" ]]; then
    echo "profile: OS_DIR is not set" >&2
    return 2
  fi
  if [[ "$name" == "core" ]]; then
    echo "profile: 'core' is a reserved name and cannot be loaded" >&2
    return 3
  fi

  if [[ -f "${OS_DIR}/users/${name}/profile.jsonc" ]]; then
    _profile_real_merge users "$name"
  else
    local config_json rc=0
    config_json="$(load_user_config "$name" 2>/dev/null)" || rc=$?
    case "$rc" in
    0 | 1) printf '%s\n' "$config_json" ;;
    *) echo "profile: cannot load user '${name}'" >&2; return 2 ;;
    esac
  fi
}

# Transient scaffold (removed at end of migration) — synthesize the same
# effective config from the legacy install.template.jsonc (machine props,
# core+specific) deep-merged with config.jsonc (software, core+specific).
# A template-less host (e.g. arch-data) synthesizes from its config alone.
_load_profile_synthesize() {
  local name="$1" rc=0
  local hosts_dir="${OS_DIR}/hosts"

  local template_json='{}'
  if [[ -f "${hosts_dir}/core/install.template.jsonc" ]] \
     && { [[ -f "${hosts_dir}/${name}/install.template.jsonc" ]] \
          || [[ -f "${hosts_dir}/vm/${name}/install.template.jsonc" ]]; }; then
    template_json="$(picker_load_template "$hosts_dir" "$name")" \
      || template_json='{}'
  fi

  local config_json
  config_json="$(load_host_config "$name" 2>/dev/null)" || rc=$?
  case "$rc" in
  0 | 1) ;;             # 1 = specific missing, core-only is fine
  *) config_json='{}' ;;
  esac
  [[ -n "$config_json" ]] || config_json='{}'

  _configs_merge "$template_json" "$config_json"
}

# =============================================================================
# CLOSED-SCHEMA VALIDATION (ADR 0036, amends ADR 0015)
# =============================================================================
# Every authored config is validated against a closed schema at load: any
# unknown key at any depth aborts with its path, before any disk write. The
# schema is expressed as path patterns; a pattern segment is a literal key,
# `*` (any object key — open subtree), or a trailing `[]` (array). The union
# below enumerates every currently-valid key across the legacy install.jsonc
# and host/user config.jsonc (their union); reads (accessors.sh) and these
# patterns must stay in lockstep — a drift guard in the bats suite asserts
# every _INSTALL_CONFIG_SCHEMA read-path is covered here.

_PROFILE_SCHEMA_host=(
  # — system identity —
  "system.hostname" "system.locale" "system.timezone" "system.keymap"
  "host_profile" "dotfiles_repo"
  # — options (kernel is a string|array union — the [] form admits both) —
  "options.kernel[]" "options.bootloader" "options.encryption"
  "options.swap" "options.swap_size" "options.esp_size" "options.age_key_url"
  "options.impermanence.enabled" "options.impermanence.dataset"
  "options.impermanence.mount"
  # — environment (desktop/gpu are string|array unions) —
  "environment.desktop[]" "environment.gpu[]"
  # — layout scalars —
  "ashift" "os_size" "os_pool_name" "storage_pool_name" "storage_mount"
  "mode" "disk"
  # — os_pool object (skeleton; disks resolved at install time) —
  "os_pool.pool_name" "os_pool.ashift" "os_pool.topology" "os_pool.disks[]"
  # — storage_groups[] —
  "storage_groups[].name" "storage_groups[].topology"
  "storage_groups[].mount" "storage_groups[].ashift"
  "storage_groups[].owners[]" "storage_groups[].disks[]"
  # — data_pools[] —
  "data_pools[].name" "data_pools[].topology" "data_pools[].mount"
  "data_pools[].ashift" "data_pools[].owners[]" "data_pools[].disks[]"
  # — post-install toggles —
  "post_install.backup" "post_install.security"
  # — packages (open category objects) —
  "packages.extra[]" "packages.groups.*[]"
  "packages.repo.*[]" "packages.aur.*[]"
  # — host software (config.jsonc) —
  "users[]" "system_programs[]" "sysctl.*"
  "persist.directories[]" "persist.files[]"
)

_PROFILE_SCHEMA_user=(
  "shell" "sudo" "groups[]" "programs[]" "ssh_authorized_keys[]"
  "git.name" "git.email"
)

_PROFILE_SCHEMA_program=( "name" "system" "description" )

# validate_config_schema <kind> <json> — kind ∈ {host, user, program}.
# Emits nothing and returns 0 when every key is enumerated; otherwise calls
# error() with the shortest offending path and returns non-zero. Pure: reads
# the JSON arg only, never disks.
validate_config_schema() {
  local kind="$1" json="$2"
  case "$kind" in
  host | user | program) ;;
  *) error "validate_config_schema: unknown schema kind '${kind}'"; return 1 ;;
  esac

  local -n _pats="_PROFILE_SCHEMA_${kind}"
  local pats
  printf -v pats '%s\n' "${_pats[@]}"

  local bad
  bad="$(jq -rn --argjson cfg "$json" --arg pats "$pats" '
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
  ')" || { error "validate_config_schema: jq failed for ${kind} schema"; \
           return 1; }

  if [[ -n "$bad" ]]; then
    error "Unknown key '${bad}' in ${kind} config (closed schema, ADR 0036)." \
          "Fix the typo or remove it before any disk is touched."
    return 1
  fi
}

# validate_profile <name> — the validate-at-load entrypoint. Loads and
# closed-schema-validates the host profile, every referenced user profile,
# and every referenced program config.jsonc (host system_programs + each
# user's programs). Aborts via error() with the offending path on the first
# failure; runs before any disk-touching phase. Requires OS_DIR set.
validate_profile() {
  local name="$1"

  local host_json
  host_json="$(load_profile "$name")" \
    || { error "validate_profile: cannot load host profile '${name}'"; \
         return 1; }
  validate_config_schema host "$host_json" || return 1

  local -a users
  mapfile -t users < <(printf '%s' "$host_json" | jq -r '.users[]?')

  local u uj
  for u in "${users[@]}"; do
    [[ -n "$u" ]] || continue
    uj="$(load_user_profile "$u")" \
      || { error "validate_profile: cannot load user profile '${u}'"; \
           return 1; }
    validate_config_schema user "$uj" || return 1
  done

  configs_build_registry

  local -a sysprogs uprogs
  mapfile -t sysprogs < <(printf '%s' "$host_json" \
    | jq -r '.system_programs[]?')
  _validate_program_configs "${sysprogs[@]}" || return 1

  for u in "${users[@]}"; do
    [[ -n "$u" ]] || continue
    uj="$(load_user_profile "$u")"
    mapfile -t uprogs < <(printf '%s' "$uj" | jq -r '.programs[]?')
    _validate_program_configs "${uprogs[@]}" || return 1
  done
}

# Closed-schema-validate each named program's config.jsonc. Resolves names
# via the registry; a missing program / config.jsonc / parse error aborts.
_validate_program_configs() {
  local p rel cfg json
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    if ! rel="$(resolve_program "$p")"; then
      error "validate_profile: program '${p}' not found under" \
            "${OS_DIR}/programs/<cat>/${p}/"
      return 1
    fi
    cfg="${OS_DIR}/programs/${rel}/config.jsonc"
    if ! json="$(jsonc_strip "$cfg" 2>/dev/null | jq '.' 2>/dev/null)"; then
      error "validate_profile: program '${p}' config.jsonc missing or" \
            "unparseable at ${cfg}"
      return 1
    fi
    validate_config_schema program "$json" || return 1
  done
}
