#!/usr/bin/env bash
# =============================================================================
# lib/config/validation.sh — Single validation seam for all config contracts
# =============================================================================
# Requires: lib/common.sh, lib/config/environment.sh,
# lib/config/program-registry.sh already sourced.
#
# Public API:
#   validation_check_install_context — validate system fields, disk paths,
#                                      environment, and program contracts in
#                                      one pass; exits via error() on any
#                                      failure
#   validation_check_staging <dir>   — verify staged runtime tree at <dir> is
#                                      complete; exits via error() on any
#                                      missing piece
#
# The single place "is this install context valid?" is answered: the three
# former layers (config-load, program contracts, staging integrity) are owned
# here, so callers get one seam and one error convention.
#
# Used by: 03-install.sh, lib/feature-audit/manifest.sh,
# lib/guided/controller.sh, vm/lib/profile-validate.sh.
# =============================================================================

# shellcheck source=../impermanence-common.sh
source "${BASH_SOURCE[0]%/*}/../impermanence-common.sh"
# shellcheck source=./validation-programs.sh
declare -F _validation_preflight_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/validation-programs.sh"

# =============================================================================
# SYSTEM FIELDS
# =============================================================================
# Sets RESOLVED_HOSTNAME and RESOLVED_HOST_PROFILE; requires CONFIG_FILE set.
# host_profile is dropped as a field (ADR 0036) — the --profile arg / host
# directory name is the identity, and it equals the resolved hostname.

_validation_system_fields() {
  local hostname
  hostname="$(install_config_hostname)"
  # The pre-wipe --check pass must not prompt: the real run asks for it.
  [[ -z "$hostname" && "${INSTALL_CHECK_ONLY:-0}" == "1" ]] \
    && hostname=check-only
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
  # shellcheck disable=SC2034 # consumed by chroot_configure_system() in chroot.sh
  RESOLVED_HOSTNAME="$hostname"

  # The Host Profile behind this hostname (ADR 0020: `desktop` installs
  # `eterniox`), for profile_loader_load and secrets_load.
  # shellcheck disable=SC2034 # consumed by secrets_load and the runner
  RESOLVED_HOST_PROFILE="$(profile_loader_name_for_hostname "$hostname")"

  config_required '.system.locale' 'system.locale'
  # Timezone is NOT required in the config (ADR 0118): it is resolved at persist
  # time — an explicit/guided value wins, else geo-IP autodetect, else
  # UTC — so an absent field is valid, not an error.
}

# =============================================================================
# PUBLIC API
# =============================================================================

# =============================================================================
# IMPERMANENCE
# =============================================================================
# When options.impermanence.enabled=true, the persist dataset must live on
# the same pool as the OS root (os_pool_name). Cross-pool rollback would
# leave persist orphaned if the OS pool is recreated.

_validation_impermanence() {
  local enabled dataset pool os_pool
  enabled="$(install_config_impermanence_enabled)"
  [[ "$enabled" == "true" ]] || return 0
  # The <pool>/<path> + same-pool rule is ZFS-specific. A btrfs root persists
  # onto a plain /persist directory on @ (the never-rolled-back root subvol),
  # so there is no dataset/pool to validate — skip it for non-zfs (ADR 0044).
  [[ "$(install_config_filesystem)" == "zfs" ]] || return 0
  dataset="$(install_config_impermanence_dataset)"
  [[ "$dataset" == */* ]] || \
    error "Invalid options.impermanence.dataset '${dataset}':" \
          "must be <pool>/<path>."
  pool="${dataset%%/*}"
  os_pool="$(install_config_os_pool_name)"
  [[ "$pool" == "$os_pool" ]] || \
    error "options.impermanence.dataset '${dataset}' must be on the" \
          "same pool as ${os_pool}/ROOT/arch."
}

# Impermanence is forbidden on a hybrid AMD+NVIDIA GPU (ADR 0060): on a
# rolled-back root the graphical login hits a logind race that black-screens the
# compositor (only ever reproduced on the hybrid laptop). Runs AFTER
# environment_resolve so `gpu: "auto"` is judged on detected hardware.
_validation_impermanence_gpu() {
  [[ "$(install_config_impermanence_enabled)" == "true" ]] || return 0
  local vendor has_amd=false has_nvidia=false
  for vendor in "${ENVIRONMENT_GPU[@]:-}"; do
    [[ "$vendor" == "amd" ]]    && has_amd=true
    [[ "$vendor" == "nvidia" ]] && has_nvidia=true
  done
  [[ "$has_amd" == true && "$has_nvidia" == true ]] && error \
    "options.impermanence.enabled is not allowed on a hybrid AMD+NVIDIA GPU" \
    "(resolved GPU: ${ENVIRONMENT_GPU[*]:-none}). Disable impermanence or run" \
    "on single-GPU hardware (ADR 0060)."
  return 0
}


# =============================================================================
# FILESYSTEM ADAPTER CONTRACT (ADR 0040)
# =============================================================================
# Config-sanity rules over the `filesystem` discriminator, independent of which
# adapter is actually built (the layout-dispatch seam owns "only ZFS is
# implemented"). Each rule names the offending path and aborts via error().

_VALIDATION_KNOWN_FILESYSTEMS=(zfs btrfs ext4 xfs)

_validation_filesystem() {
  local filesystem; filesystem="$(install_config_filesystem)"

  local known=0 known_filesystem
  for known_filesystem in "${_VALIDATION_KNOWN_FILESYSTEMS[@]}"; do
    [[ "$filesystem" == "$known_filesystem" ]] && { known=1; break; }
  done
  ((known)) || error "Unknown filesystem '${filesystem}'." \
    "Valid: ${_VALIDATION_KNOWN_FILESYSTEMS[*]}."

  # Method must match the filesystem: ZFS uses native AES, every other
  # filesystem uses LUKS. The accessor derives the right default, so only an
  # explicit mismatch trips this.
  local method want
  method="$(install_config_encryption_method)"
  [[ "$filesystem" == "zfs" ]] && want="native" || want="luks"
  [[ "$method" == "$want" ]] || error \
    "options.encryption_method '${method}' is invalid for filesystem" \
    "'${filesystem}' (expected '${want}')."

  # Impermanence needs native snapshots, so it is offered only on ZFS / btrfs.
  if [[ "$(install_config_impermanence_enabled)" == "true" ]] \
     && [[ "$filesystem" != "zfs" && "$filesystem" != "btrfs" ]]; then
    error "options.impermanence.enabled requires a snapshotting filesystem" \
      "(zfs or btrfs), not '${filesystem}'."
  fi
}

# Per-group filesystem contract (ADR 0043) — over each Standalone Data Pool
# (data_pools[]) and Storage Group (storage_groups[]). A group may pick its own
# filesystem (default inherits the root); the value must be known, its topology
# valid for that filesystem, and ext4/xfs single-disk only. Names the offending
# group. Config-sanity only, like _validation_filesystem.
_validation_group_filesystems() {
  local i count
  count="$(install_config_data_pools_count)"
  for ((i = 0; i < count; i++)); do
    _validation_one_group "data pool" \
      "$(install_config_data_pool_name "$i")" \
      "$(install_config_data_pool_filesystem "$i")" \
      "$(config_optional ".data_pools[$i].disk_count")" \
      "$(config_optional ".data_pools[$i].topology")"
  done
  count="$(install_config_storage_groups_count)"
  for ((i = 0; i < count; i++)); do
    _validation_one_group "storage group" \
      "$(install_config_storage_group_name "$i")" \
      "$(install_config_storage_group_filesystem "$i")" \
      "$(config_optional ".storage_groups[$i].disk_count")" \
      "$(config_optional ".storage_groups[$i].topology")"
  done
}

# Validate one group's filesystem/topology/disk-count. $kind is a human label
# ("data pool" / "storage group") used in error messages.
_validation_one_group() {
  local kind="$1" name="$2" filesystem="$3" disk_count="$4" topology="$5"
  local known=0 known_filesystem
  for known_filesystem in "${_VALIDATION_KNOWN_FILESYSTEMS[@]}"; do
    [[ "$filesystem" == "$known_filesystem" ]] && { known=1; break; }
  done
  ((known)) \
    || error "Unknown filesystem '${filesystem}' on ${kind} '${name}'." \
    "Valid: ${_VALIDATION_KNOWN_FILESYSTEMS[*]}."

  # A Storage Group folds into the single Combined Data Pool (one zpool), so it
  # can only be zfs — a non-zfs group can't be a vdev of a zpool. A mixed-
  # filesystem data disk belongs in data_pools[] (its own Standalone Data Pool).
  if [[ "$kind" == "storage group" && "$filesystem" != "zfs" ]]; then
    error "Storage group '${name}' is ${filesystem}, but a storage group" \
      "folds into" \
      "the zfs Combined Data Pool. Put a non-zfs disk in data_pools[] instead."
  fi

  # ext4/xfs have no multi-disk story (no mdadm/LVM) — single-disk only.
  if [[ "$filesystem" == "ext4" || "$filesystem" == "xfs" ]]; then
    if [[ -n "$disk_count" ]] && ((disk_count > 1)); then
      error "${kind^} '${name}' is ${filesystem} (single-disk only) but" \
        "declares" \
        "disk_count ${disk_count}. Use zfs or btrfs for a multi-disk group."
    fi
  fi

  # Topology must be valid for the filesystem; an absent topology (raw, not the
  # accessor's 'stripe' default) is unconstrained.
  _validation_topology_for_filesystem "$name" "$filesystem" "$topology"
}

# Valid topologies per filesystem (ADR 0043): zfs native vdev types; btrfs
# native profiles; ext4/xfs single only. An empty topology is unconstrained
# (the layout adapter applies the filesystem's default). Names the offending
# pool on a mismatch.
_validation_topology_for_filesystem() {
  local name="$1" filesystem="$2" topology="$3" valid valid_topology
  [[ -z "$topology" ]] && return 0
  case "$filesystem" in
  zfs) valid="mirror stripe independent raidz raidz1 raidz2 none" ;;
  btrfs) valid="single raid0 raid1 raid10" ;;
  ext4 | xfs) valid="single" ;;
  *) return 0 ;;
  esac
  for valid_topology in $valid; do
    [[ "$topology" == "$valid_topology" ]] && return 0
  done
  error "Data pool '${name}' (${filesystem}) has invalid topology" \
    "'${topology}'." \
    "Valid for ${filesystem}: ${valid}."
}

# Validate persist paths from the effective (merged) config JSON.
# Errors abort via error(); warnings are printed via warn().
_validation_persist() {
  local host_json="$1"
  local any_error=0
  local path

  local -a directories files
  mapfile -t directories  < <(printf '%s' "$host_json" \
    | jq -r '(.persist.directories // [])[]')
  mapfile -t files < <(printf '%s' "$host_json" \
    | jq -r '(.persist.files       // [])[]')

  local impermanence_enabled
  impermanence_enabled="$(install_config_impermanence_enabled)"
  if [[ "$impermanence_enabled" != "true" ]] \
     && (( ${#directories[@]} + ${#files[@]} > 0 )); then
    warn "Host declares persist paths but impermanence is disabled."
  fi

  for path in "${directories[@]}"; do
    [[ -z "$path" ]] && continue
    _validation_persist_one dir "$path" || any_error=1
  done
  for path in "${files[@]}"; do
    [[ -z "$path" ]] && continue
    _validation_persist_one file "$path" || any_error=1
  done

  (( any_error == 0 )) || error "Persist path validation failed."
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

  local persistent_dataset
  for persistent_dataset in "${_VALIDATION_PERSISTENT_DATASETS[@]}"; do
    if [[ "$path" == "$persistent_dataset" \
       || "$path" == "$persistent_dataset"/* ]]; then
      warn "Persist path '${path}' is under ${persistent_dataset}," \
           "already persistent." \
           "Redundant."
      return 0
    fi
  done

  local curated_path
  for curated_path in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    if [[ "$path" == "$curated_path" || "$path" == "$curated_path"/* ]]; then
      warn "Persist path '${path}' is in curated defaults. Redundant."
      return 0
    fi
  done

  return 0
}

# Validate all config contracts in one pass.
# Sets RESOLVED_HOSTNAME and RESOLVED_HOST_PROFILE.
# Requires CONFIG_FILE, INSTALL_MODE, INSTALLER_DIR set.
# Exits via error() on the first fatal failure; collects all program failures
# before exiting so every problem is visible at once.
validation_check_install_context() {
  section "Validating Install Context"

  _validation_system_fields

  _validation_filesystem

  _validation_group_filesystems

  layout_validate

  _validation_impermanence

  environment_resolve

  _validation_impermanence_gpu

  program_registry_build

  # A name is either a Program or a package, never both. Checked against the
  # EFFECTIVE CONFIG so every front-end aborts identically, before any disk is
  # touched. Replaces the guided-only promotion rule.
  local effective_json
  # shellcheck disable=SC2153 # CONFIG_FILE is the Install Config global
  effective_json="$(jsonc_strip "$CONFIG_FILE")"
  program_registry_validate_package_exclusivity "$effective_json" \
    "$CONFIG_FILE" \
    || error "Package/Program name collision — see above."

  _validation_preflight_programs "$RESOLVED_HOST_PROFILE"

  # The effective config, not a profile looked up by name: it carries the
  # profile's persist paths and any Guided-added ones.
  _validation_persist "$effective_json"

  info "Install context valid."
}

# Verify the staged runtime tree at <dir> is complete.
# Called from profiles.sh after runner_stage_runtime.
validation_check_staging() {
  local target="$1"
  [[ -d "$target/programs" ]] ||
    error "Staging incomplete: ${target}/programs missing."
  local staged_file
  for staged_file in "${_STAGED_RUNTIME_FILES[@]}"; do
    [[ -e "$target/${staged_file}" ]] ||
      error "Staging incomplete: ${target}/${staged_file} missing."
  done
}
