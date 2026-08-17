#!/usr/bin/env bash
# =============================================================================
# lib/config/validation.sh — Single validation seam for all config contracts
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

# shellcheck source=../impermanence-common.sh
source "${BASH_SOURCE[0]%/*}/../impermanence-common.sh"

# =============================================================================
# SYSTEM FIELDS
# =============================================================================
# Sets RESOLVED_HOSTNAME and RESOLVED_HOST_PROFILE; requires CONFIG_FILE set.
# host_profile is dropped as a field (ADR 0036) — the --profile arg / host
# directory name is the identity, and it equals the resolved hostname.

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

  # shellcheck disable=SC2034 # consumed by callers passing it to
  # load_profile and secrets_load.
  RESOLVED_HOST_PROFILE="$hostname"

  cfg '.system.locale' 'system.locale'
  cfg '.system.timezone' 'system.timezone'
}

# =============================================================================
# PROGRAM PREFLIGHT
# =============================================================================
# Validates all program contracts for <profile> and its users.
# Requires OS_DIR set and configs_build_registry already called.
# Returns immediately (no-op) if no core profiles are present — profiles will
# be skipped at runtime and there is nothing to validate.
# Exits via error() on any validation failure or corrupt core profile.

_validation_preflight_programs() {
  local profile="$1"
  [[ -f "${OS_DIR}/hosts/core/profile.jsonc" ]] || return 0
  [[ -f "${OS_DIR}/users/core/profile.jsonc" ]] || return 0

  local host_json rc=0
  host_json="$(load_profile "$profile" 2>/dev/null)" || rc=$?
  case "$rc" in
  1) return 0 ;;
  2) error "validation: cannot load host core profile." ;;
  3) error "validation: host profile '${profile}' is reserved." ;;
  esac

  local -a sys_progs users
  mapfile -t sys_progs < <(printf '%s' "$host_json" \
    | jq -r '.host_programs[]?')
  mapfile -t users     < <(printf '%s' "$host_json" | jq -r '.users[]?')

  local u
  for u in "${users[@]}"; do
    [[ -d "${OS_DIR}/users/${u}" ]] ||
      error "Host config references user '${u}' but" \
            "${OS_DIR}/users/${u}/ does not exist."
  done

  local any_fail=0
  if ((${#sys_progs[@]} > 0)); then
    validate_programs "host" "${sys_progs[@]}" || any_fail=1
  fi

  # System-program JSON array for the requires-order check below (ADR 0065),
  # built once — it is the same for every user. Drops the empty-list sentinel.
  local _sys_json
  _sys_json="$(printf '%s\n' "${sys_progs[@]+"${sys_progs[@]}"}" \
    | jq -R . | jq -sc 'map(select(length > 0))')"

  local uj urc
  local -a uprogs
  for u in "${users[@]}"; do
    urc=0
    uj="$(load_user_profile "$u" 2>/dev/null)" || urc=$?
    case "$urc" in
    0 | 1) ;;
    *) echo "validation: cannot load user profile '${u}'" >&2
       any_fail=1; continue ;;
    esac
    mapfile -t uprogs < <(printf '%s' "$uj" | jq -r '.programs[]?')
    # Reconcile each user program reference (ADR 0036): system:false installs
    # at user level; a host-installed Host Program is a no-op; a Host Program
    # no host installs aborts (reconcile prints the actionable why).
    local _up
    for _up in "${uprogs[@]}"; do
      reconcile_user_program "$_up" "${sys_progs[@]+"${sys_progs[@]}"}" \
        >/dev/null || any_fail=1
    done
    # Dependency ordering (ADR 0065): each program's `requires` must be
    # installed first — a Host Program or an earlier entry in this list.
    _validation_check_requires_order "$u" "$_sys_json" \
      "$(printf '%s' "$uj" | jq -c '.programs // []')" || any_fail=1
  done

  ((any_fail == 0)) || \
    error "Program contracts failed. Fix the errors above and re-run."
}

# =============================================================================
# PROGRAM DEPENDENCY ORDERING (ADR 0065)
# =============================================================================
# A Program may declare `requires: ["podman", ...]` — other Programs whose
# install-time SETUP (package + side effects like podman's subuid/subgid) must
# be in place before it runs. Because the Runner installs a user's programs
# one-by-one in declared order, the dependency must already be installed when
# the dependent runs. Enforced here, before any side effect, so a mis-ordered
# or incomplete list aborts up front with an actionable message instead of a
# hard failure part-way through the install (the class of bug that let a guided
# selection put searxng before podman).

# _validation_index_of <needle> <hay...> — 0-based index of the first <hay>
# equal to <needle>, or empty when absent. Pure.
_validation_index_of() {
  local needle="$1"; shift
  local i=0 x
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
}

# _validation_program_requires <prog> — the program's declared `requires` list,
# one per line (empty when none or the program has no config). Pure over OS_DIR.
_validation_program_requires() {
  local rel cf
  rel="$(resolve_program "$1" 2>/dev/null)" || return 0
  cf="${OS_DIR}/programs/${rel}/config.jsonc"
  [[ -f "$cf" ]] || return 0
  jsonc_strip "$cf" | jq -r '.requires[]?' 2>/dev/null
}

# _validation_check_requires_order <user> <sys_json> <uprogs_json> — enforce
# every user program's `requires` for one user. A required program is satisfied
# when it is a Host Program (installed before all user programs) or
# appears EARLIER in this user's own list. Prints an actionable line per
# violation and returns 1 if any; 0 when clean. Pure over OS_DIR + the two JSON
# array args (host_programs, the user's programs).
_validation_check_requires_order() {
  local user="$1" sys_json="$2" up_json="$3" fail=0
  local -a up sys
  mapfile -t up  < <(printf '%s' "$up_json"  | jq -r '.[]?')
  mapfile -t sys < <(printf '%s' "$sys_json" | jq -r '.[]?')
  local i p r ri
  for i in "${!up[@]}"; do
    p="${up[$i]}"
    while IFS= read -r r; do
      [[ -n "$r" ]] || continue
      # A Host Program is installed before every user program.
      local _si; _si="$(_validation_index_of "$r" "${sys[@]+"${sys[@]}"}")"
      [[ -n "$_si" ]] && continue
      ri="$(_validation_index_of "$r" "${up[@]}")"
      if [[ -z "$ri" ]]; then
        echo "User '${user}': program '${p}' requires '${r}', which is not" \
             "declared in ${user}'s programs. Add '${r}' before '${p}'." >&2
        fail=1
      elif ((ri >= i)); then
        echo "User '${user}': program '${p}' requires '${r}' installed first," \
             "but '${r}' is listed after it. Move '${r}' before '${p}'." >&2
        fail=1
      fi
    done < <(_validation_program_requires "$p")
  done
  return "$fail"
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

# Impermanence is forbidden on a hybrid AMD+NVIDIA GPU (ADR 0060). On a
# rolled-back impermanent root the graphical login hits a logind-session race
# that black-screens the compositor; it was only ever reproduced on the hybrid
# laptop, so the ban targets that combination and leaves single-GPU impermanence
# untouched. Runs AFTER resolve_environment (it reads the resolved
# ENVIRONMENT_GPU array), so `gpu: "auto"` is judged on the hardware detected at
# install time.
# Desktop-independent by design — the fault is impermanence, not the desktop.
_validation_impermanence_gpu() {
  [[ "$(install_config_impermanence_enabled)" == "true" ]] || return 0
  local v has_amd=false has_nvidia=false
  for v in "${ENVIRONMENT_GPU[@]:-}"; do
    [[ "$v" == "amd" ]]    && has_amd=true
    [[ "$v" == "nvidia" ]] && has_nvidia=true
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
  local fs; fs="$(install_config_filesystem)"

  local known=0 f
  for f in "${_VALIDATION_KNOWN_FILESYSTEMS[@]}"; do
    [[ "$fs" == "$f" ]] && { known=1; break; }
  done
  ((known)) || error "Unknown filesystem '${fs}'." \
    "Valid: ${_VALIDATION_KNOWN_FILESYSTEMS[*]}."

  # Method must match the filesystem: ZFS uses native AES, every other
  # filesystem uses LUKS. The accessor derives the right default, so only an
  # explicit mismatch trips this.
  local method want
  method="$(install_config_encryption_method)"
  [[ "$fs" == "zfs" ]] && want="native" || want="luks"
  [[ "$method" == "$want" ]] || error \
    "options.encryption_method '${method}' is invalid for filesystem" \
    "'${fs}' (expected '${want}')."

  # Impermanence needs native snapshots, so it is offered only on ZFS / btrfs.
  if [[ "$(install_config_impermanence_enabled)" == "true" ]] \
     && [[ "$fs" != "zfs" && "$fs" != "btrfs" ]]; then
    error "options.impermanence.enabled requires a snapshotting filesystem" \
      "(zfs or btrfs), not '${fs}'."
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
      "$(cfgo ".data_pools[$i].disk_count")" \
      "$(cfgo ".data_pools[$i].topology")"
  done
  count="$(install_config_storage_groups_count)"
  for ((i = 0; i < count; i++)); do
    _validation_one_group "storage group" \
      "$(install_config_storage_group_name "$i")" \
      "$(install_config_storage_group_filesystem "$i")" \
      "$(cfgo ".storage_groups[$i].disk_count")" \
      "$(cfgo ".storage_groups[$i].topology")"
  done
}

# Validate one group's filesystem/topology/disk-count. $kind is a human label
# ("data pool" / "storage group") used in error messages.
_validation_one_group() {
  local kind="$1" name="$2" fs="$3" dc="$4" topo="$5" known=0 f
  for f in "${_VALIDATION_KNOWN_FILESYSTEMS[@]}"; do
    [[ "$fs" == "$f" ]] && { known=1; break; }
  done
  ((known)) || error "Unknown filesystem '${fs}' on ${kind} '${name}'." \
    "Valid: ${_VALIDATION_KNOWN_FILESYSTEMS[*]}."

  # A Storage Group folds into the single Combined Data Pool (one zpool), so it
  # can only be zfs — a non-zfs group can't be a vdev of a zpool. A mixed-
  # filesystem data disk belongs in data_pools[] (its own Standalone Data Pool).
  if [[ "$kind" == "storage group" && "$fs" != "zfs" ]]; then
    error "Storage group '${name}' is ${fs}, but a storage group folds into" \
      "the zfs Combined Data Pool. Put a non-zfs disk in data_pools[] instead."
  fi

  # ext4/xfs have no multi-disk story (no mdadm/LVM) — single-disk only.
  if [[ "$fs" == "ext4" || "$fs" == "xfs" ]]; then
    if [[ -n "$dc" ]] && ((dc > 1)); then
      error "${kind^} '${name}' is ${fs} (single-disk only) but declares" \
        "disk_count ${dc}. Use zfs or btrfs for a multi-disk group."
    fi
  fi

  # Topology must be valid for the filesystem; an absent topology (raw, not the
  # accessor's 'stripe' default) is unconstrained.
  _validation_topology_for_fs "$name" "$fs" "$topo"
}

# Valid topologies per filesystem (ADR 0043): zfs native vdev types; btrfs
# native profiles; ext4/xfs single only. An empty topology is unconstrained
# (the layout adapter applies the filesystem's default). Names the offending
# pool on a mismatch.
_validation_topology_for_fs() {
  local name="$1" fs="$2" topo="$3" valid t
  [[ -z "$topo" ]] && return 0
  case "$fs" in
  zfs) valid="mirror stripe independent raidz raidz1 raidz2 none" ;;
  btrfs) valid="single raid0 raid1 raid10" ;;
  ext4 | xfs) valid="single" ;;
  *) return 0 ;;
  esac
  for t in $valid; do
    [[ "$topo" == "$t" ]] && return 0
  done
  error "Data pool '${name}' (${fs}) has invalid topology '${topo}'." \
    "Valid for ${fs}: ${valid}."
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
# Sets RESOLVED_HOSTNAME and RESOLVED_HOST_PROFILE.
# Requires CONFIG_FILE, INSTALL_MODE, OS_DIR set.
# Exits via error() on the first fatal failure; collects all program failures
# before exiting so every problem is visible at once.
validate_install_context() {
  section "Validating Install Context"

  _validation_system_fields

  _validation_filesystem

  _validation_group_filesystems

  layout_validate

  _validation_impermanence

  resolve_environment

  _validation_impermanence_gpu

  configs_build_registry

  # A name is either a Program or a package, never both. Checked against the
  # EFFECTIVE CONFIG so every front-end aborts identically, before any disk is
  # touched. Replaces the guided-only promotion rule.
  local _eff_json
  _eff_json="$(jsonc_strip "$CONFIG_FILE")"
  validate_package_program_exclusivity "$_eff_json" "$CONFIG_FILE" \
    || error "Package/Program name collision — see above."

  _validation_preflight_programs "$RESOLVED_HOST_PROFILE"

  local _host_json
  _host_json="$(load_profile "$RESOLVED_HOST_PROFILE" 2>/dev/null || \
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
