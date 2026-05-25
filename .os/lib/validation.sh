#!/usr/bin/env bash
# =============================================================================
# lib/validation.sh — Single validation seam for all config contracts
# =============================================================================
# Sourced by 03-install.sh after common.sh, config.sh, and configs.sh.
# Requires: common.sh, environment.sh (via config.sh),
# configs.sh already sourced.
#
# Public API:
#   validate_install_context    — validate system fields, disk paths,
#                                 environment, and program contracts in
#                                 one pass;
#                                 exits via error() on any failure
#   validate_staging <dir>      — verify staged runtime tree at <dir> is
#                                 complete; exits via error() on any
#                                 missing piece
#
# This is the single place where "is this install context valid?" is answered.
# The three former validation layers — config-load (system fields, disks),
# program contracts (configs.sh), and staging integrity (profiles.sh) — are
# owned here. Callers get one seam and one error-signaling convention.
# =============================================================================

# shellcheck source=./impermanence-common.sh
source "${BASH_SOURCE[0]%/*}/impermanence-common.sh"

# =============================================================================
# SYSTEM FIELDS
# =============================================================================
# Sets RESOLVED_HOSTNAME; requires CONFIG_FILE to be set.

_validation_system_fields() {
  local hostname
  hostname="$(install_config_hostname)"
  if [[ -z "$hostname" ]]; then
    while true; do
      read -rp \
        "$(echo -e "${YELLOW}[?]${NC} Enter hostname for this machine: ")" \
        hostname </dev/tty
      [[ -n "$hostname" ]] && break
      warn "Hostname cannot be empty."
    done
    info "Hostname: ${hostname}"
  fi
  [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] ||
    error "Invalid hostname '${hostname}'." \
          "Use letters, digits, hyphens only (no leading/trailing hyphen)."
  # shellcheck disable=SC2034 # consumed by configure_system() in chroot.sh
  RESOLVED_HOSTNAME="$hostname"
  cfg '.system.locale' 'system.locale'
  cfg '.system.timezone' 'system.timezone'
}

# =============================================================================
# DISK VALIDATORS
# =============================================================================
# Dispatched by mode from validate_install_context.

_validation_single() {
  local d
  d="$(cfg '.disk' 'disk')"
  [[ -b "$d" ]] || error "Single disk not found: $d"
}

_validation_multi() {
  local topo
  topo="$(cfgo '.os_pool.topology')"
  if [[ -n "$topo" ]]; then
    case "$topo" in
    mirror | stripe | none) ;;
    *) error "os_pool.topology must be mirror|stripe|none, got: '${topo}'" ;;
    esac
  fi

  local cnt
  cnt="$(jsonc_strip "$CONFIG_FILE" | jq '.os_pool.disks | length')"
  ((cnt >= 1)) || error "os_pool.disks must list at least 1 disk."

  local d
  while IFS= read -r d; do
    [[ -b "$d" ]] || error "OS disk not found: $d"
  done < <(jsonc_strip "$CONFIG_FILE" | jq -r '.os_pool.disks[]')

  local sg gname gdc
  sg="$(jsonc_strip "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < sg; i++)); do
    gname="$(cfg ".storage_groups[$i].name")"
    gdc="$(jsonc_strip "$CONFIG_FILE" \
      | jq ".storage_groups[$i].disks | length")"
    ((gdc >= 1)) || error "Storage group '${gname}' has no disks."
    while IFS= read -r d; do
      [[ -b "$d" ]] || error "Group '${gname}' disk not found: $d"
    done < <(jsonc_strip "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
  done
}

# =============================================================================
# PROGRAM PREFLIGHT
# =============================================================================
# Validates all program contracts for <hostname> and its users.
# Requires OS_DIR set and configs_build_registry already called.
# Returns immediately (no-op) if no core configs are present — profiles will
# be skipped at runtime and there is nothing to validate.
# Exits via error() on any validation failure or corrupt core config.

_validation_preflight_programs() {
  local hostname="$1"
  [[ -f "${OS_DIR}/hosts/core/config.jsonc" ]] || return 0
  [[ -f "${OS_DIR}/users/core/config.jsonc" ]] || return 0

  local host_json rc=0
  host_json="$(load_host_config "$hostname" 2>/dev/null)" || rc=$?
  case "$rc" in
  1) return 0 ;;
  2) error "validation: cannot load host core config." ;;
  3) error "validation: hostname '${hostname}' is reserved." ;;
  esac

  local -a sys_progs users
  mapfile -t sys_progs < <(printf '%s' "$host_json" \
    | jq -r '.system_programs[]?')
  mapfile -t users     < <(printf '%s' "$host_json" | jq -r '.users[]?')

  local u
  for u in "${users[@]}"; do
    [[ -d "${OS_DIR}/users/${u}" ]] ||
      error "Host config references user '${u}' but" \
            "${OS_DIR}/users/${u}/ does not exist."
  done

  local any_fail=0
  if ((${#sys_progs[@]} > 0)); then
    validate_programs "true" "${sys_progs[@]}" || any_fail=1
  fi

  local uj urc
  local -a uprogs
  for u in "${users[@]}"; do
    urc=0
    uj="$(load_user_config "$u" 2>/dev/null)" || urc=$?
    case "$urc" in
    0 | 1) ;;
    *) echo "validation: cannot load user config '${u}'" >&2
       any_fail=1; continue ;;
    esac
    mapfile -t uprogs < <(printf '%s' "$uj" | jq -r '.programs[]?')
    if ((${#uprogs[@]} > 0)); then
      validate_programs "false" "${uprogs[@]}" || any_fail=1
    fi
  done

  ((any_fail == 0)) || \
    error "Program contracts failed. Fix the errors above and re-run."
}

# =============================================================================
# PUBLIC API
# =============================================================================

# =============================================================================
# IMPERMANENCE
# =============================================================================
# When options.impermanence.enabled=true, the persist dataset must live on
# the same pool as rpool/ROOT/arch (i.e. $RPOOL). Cross-pool rollback would
# leave persist orphaned if the OS pool is recreated.

_validation_impermanence() {
  local enabled dataset pool
  enabled="$(install_config_impermanence_enabled)"
  [[ "$enabled" == "true" ]] || return 0
  dataset="$(install_config_impermanence_dataset)"
  [[ "$dataset" == */* ]] || \
    error "Invalid options.impermanence.dataset '${dataset}':" \
          "must be <pool>/<path>."
  pool="${dataset%%/*}"
  [[ "$pool" == "$RPOOL" ]] || \
    error "options.impermanence.dataset '${dataset}' must be on the" \
          "same pool as rpool/ROOT/arch (${RPOOL})."
}


# Validate persist paths from a merged host config JSON.
# Errors abort via error(); warnings are printed via warn().
_validation_persist() {
  local host_json="$1"
  local any_err=0
  local path

  local -a dirs files
  mapfile -t dirs  < <(printf '%s' "$host_json" \
    | jq -r '(.persist.directories // [])[]')
  mapfile -t files < <(printf '%s' "$host_json" \
    | jq -r '(.persist.files       // [])[]')

  local imp_enabled
  imp_enabled="$(install_config_impermanence_enabled)"
  if [[ "$imp_enabled" != "true" ]] \
     && (( ${#dirs[@]} + ${#files[@]} > 0 )); then
    warn "Host declares persist paths but impermanence is disabled."
  fi

  for path in "${dirs[@]}"; do
    [[ -z "$path" ]] && continue
    _validation_persist_one dir "$path" || any_err=1
  done
  for path in "${files[@]}"; do
    [[ -z "$path" ]] && continue
    _validation_persist_one file "$path" || any_err=1
  done

  (( any_err == 0 )) || error "Persist path validation failed."
}

_VALIDATION_PERSISTENT_DATASETS=(
  /home /var/log /var/cache /var /tmp
)

# Validate one persist entry. Returns 0 on pass, 1 on (collected) error.
_validation_persist_one() {
  local kind="$1" path="$2"
  if [[ "$path" != /* ]]; then
    echo "Persist path must be absolute: '${path}'." >&2
    return 1
  fi
  if [[ "$path" == *..* || "$path" == *"~"* ]]; then
    echo "Persist path must not contain '..' or '~': '${path}'." >&2
    return 1
  fi
  if [[ "$kind" == "file" && -d "$path" ]]; then
    echo "Persist file is a directory on disk: '${path}'." \
         "Move to persist.directories." >&2
    return 1
  fi
  if [[ "$kind" == "dir" && -f "$path" ]]; then
    echo "Persist directory is a file on disk: '${path}'." \
         "Move to persist.files." >&2
    return 1
  fi

  local ds
  for ds in "${_VALIDATION_PERSISTENT_DATASETS[@]}"; do
    if [[ "$path" == "$ds" || "$path" == "$ds"/* ]]; then
      warn "Persist path '${path}' is under ${ds}, already persistent." \
           "Redundant."
      return 0
    fi
  done

  local c
  for c in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    if [[ "$path" == "$c" || "$path" == "$c"/* ]]; then
      warn "Persist path '${path}' is in curated defaults. Redundant."
      return 0
    fi
  done

  return 0
}

# Validate all config contracts in one pass.
# Sets RESOLVED_HOSTNAME. Requires CONFIG_FILE, INSTALL_MODE, OS_DIR set.
# Exits via error() on the first fatal failure; collects all program failures
# before exiting so every problem is visible at once.
validate_install_context() {
  section "Validating Install Context"

  _validation_system_fields

  local validator="_validation_${INSTALL_MODE}"
  if declare -F "$validator" >/dev/null; then
    "$validator"
  else
    error "No validator for mode '${INSTALL_MODE}'" \
          "(expected function ${validator})."
  fi

  _validation_impermanence

  resolve_environment

  configs_build_registry
  _validation_preflight_programs "$RESOLVED_HOSTNAME"

  local _host_json
  _host_json="$(load_host_config "$RESOLVED_HOSTNAME" 2>/dev/null || \
    printf '{}')"
  _validation_persist "$_host_json"

  info "Install context valid."
}

# Verify the staged runtime tree at <dir> is complete.
# Called from profiles.sh after _profiles_stage_runtime.
validate_staging() {
  local target="$1"
  [[ -d "$target/programs" ]] ||
    error "Staging incomplete: ${target}/programs missing."
  local f
  for f in "${_STAGED_RUNTIME_FILES[@]}"; do
    [[ -e "$target/${f}" ]] ||
      error "Staging incomplete: ${target}/${f} missing."
  done
}
