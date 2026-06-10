#!/usr/bin/env bash
# =============================================================================
# install.sh — single entry point for the Arch Linux ZFS installer
# =============================================================================
# Runs the three numbered scripts in order:
#   1. 01-bootstrap-zfs.sh — adds archzfs and loads ZFS modules on the live ISO
#   2. 02-wipe.sh          — wipes only the install's target disks, resolved
#                            from the config and passed explicitly
#   3. 03-install.sh       — partitions, pacstraps, configures, runs profiles
#
# The numbered scripts remain individually runnable for debugging. An optional
# positional argument is forwarded to 03-install.sh as an alternate config path.
# Recognised flags are stripped here and re-emitted to the numbered scripts.
#
# USAGE:
#   ./install.sh                           # uses install.jsonc next to this
#                                          # file
#   ./install.sh /path/to/install.jsonc    # alternate config
#   ./install.sh -y                        # unattended (no prompts)
#   ./install.sh --unattended /path/cfg    # unattended + alternate config
#
# OPTIONS:
#   -y, --unattended   Bypass every interactive confirmation prompt — disk
#                      selection, the WIPE confirmation, and the final
#                      "Proceed?" summary. Hostname must be set in the config
#                      beforehand; the hostname prompt is not bypassed.
#   -h, --help         Print this help and exit.
# =============================================================================

set -Eeuo pipefail
_install_on_err() {
  # Only the top-level shell reports; `set -E` also fires this inside command
  # substitutions, which would double-print the same abort.
  (( BASH_SUBSHELL == 0 )) || return 0
  echo -e "\n\033[0;31m[install.sh]\033[0m aborted at line $1." >&2
}
trap '_install_on_err "$LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target Resolver — used to scope the wipe to the install's target disks.
# shellcheck source=lib/wipe/targets.sh
source "${SCRIPT_DIR}/lib/wipe/targets.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS] [CONFIG_FILE]

Single entry point for the Arch Linux ZFS installer. Runs, in order:
  1. 01-bootstrap-zfs.sh
  2. 02-wipe.sh
  3. 03-install.sh [CONFIG_FILE]

Options:
  --profile <name>   Host Profile to install (hosts/<name>/). With
                     --print-config, the only profile action wired today.
  --print-config     Validate the --profile against the closed schema,
                     assemble the effective config, print it to stdout, and
                     exit. No disk phase runs (01/02/03 never start).
  -y, --unattended   Bypass every interactive confirmation prompt (disk
                     selection, "WIPE" confirmation, final "Proceed?").
                     Hostname must be set in install.jsonc beforehand.
  -h, --help         Show this help and exit.
EOF
}

# _install_pick_assignment <profile_json>
# Interactive disk resolution for `--profile`: the profile declares the layout
# (single via .mode/.disk, multi via .os_pool.topology) and the operator picks
# only the disks (ADR 0036). Emits the assignment JSON consumed by
# assemble_profile_config. A profile that declares no layout yet (un-migrated,
# synthesized) aborts with guidance to use the positional config seam meanwhile.
# Only os_pool is resolved here — per-group storage_groups/data_pools picking is
# a follow-up; the single-pool hosts migrated first need only this.
_install_pick_assignment() {
  local profile_json="$1" mode topology picked live_set
  local -a candidates disks

  mode="$(jq -r '
    .mode // (if (.os_pool.topology // "") != "" then "multi"
              elif (.disk // "") != ""           then "single"
              else "" end)' <<<"$profile_json")"
  if [[ -z "$mode" || "$mode" == null ]]; then
    echo "[install.sh] profile declares no layout (mode / os_pool) yet." >&2
    echo "             A migrated profile.jsonc must declare the pool" \
         "skeleton; pass a config file meanwhile." >&2
    return 2
  fi

  live_set="$(live_medium_disks)"
  mapfile -t candidates < <(picker_enum_disks "$live_set")
  (( ${#candidates[@]} )) \
    || { echo "[install.sh] no /dev/disk/by-id/* candidates found" >&2; \
         return 1; }

  picked="$(printf '%s\n' "${candidates[@]}" | fzf --multi --reverse \
    --prompt='disks (TAB=multi, ENTER=confirm)> ' \
    --preview="bash -c 'source \"$OS_DIR/lib/picker.sh\"; \
      picker_format_disk_preview {}'" \
    --preview-window=right,60%)" \
    || { echo "[install.sh] no disks selected" >&2; return 1; }
  [[ -n "$picked" ]] || { echo "[install.sh] no disks selected" >&2; return 1; }
  mapfile -t disks <<< "$picked"

  if [[ "$mode" == single ]]; then
    picker_validate_layout single "${#disks[@]}" || return 1
    jq -n --arg d "${disks[0]}" '{mode:"single", disk:$d}'
  else
    topology="$(jq -r '.os_pool.topology // "stripe"' <<<"$profile_json")"
    picker_validate_layout "$topology" "${#disks[@]}" || return 1
    jq -n --argjson ds "$(printf '%s\n' "${disks[@]}" | jq -R . | jq -s .)" \
      '{mode:"multi", os_pool:$ds}'
  fi
}

forward_args=()
positional_args=()
profile_name=""
print_config=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --unattended)
      export INSTALL_UNATTENDED=1
      forward_args+=(--unattended)
      shift
      ;;
    --profile)
      profile_name="${2:?--profile requires a name}"
      shift 2
      ;;
    --profile=*)
      profile_name="${1#*=}"
      shift
      ;;
    --print-config)
      print_config=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional_args+=("$1")
        shift
      done
      ;;
    -*)
      echo "[install.sh] Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

# --print-config: validate the named Host Profile against the closed schema,
# assemble the effective config, and emit it to stdout — then exit. Runs
# before any disk-touching phase (01/02/03 never start), so a typo'd key
# aborts with its path before a disk is touched (ADR 0036). No libvirt, no
# writes. OS_DIR honours an existing value (tests) and defaults to this dir.
if [[ -n "$print_config" ]]; then
  if [[ -z "$profile_name" ]]; then
    echo "[install.sh] --print-config requires --profile <name>" >&2
    exit 2
  fi
  export OS_DIR="${OS_DIR:-$SCRIPT_DIR}"
  # shellcheck source=lib/common.sh
  source "${SCRIPT_DIR}/lib/common.sh"
  # shellcheck source=lib/config/profile.sh
  source "${SCRIPT_DIR}/lib/config/profile.sh"
  validate_profile "$profile_name"
  load_profile "$profile_name"
  exit 0
fi

# Interactive --profile front-end: validate the named Host Profile against the
# closed schema, let the operator pick disks, assemble the effective config in
# tmpfs (never committed — ADR 0036), and hand it to the back-end as a positional
# config. The picker resolves only disks; layout/identity come from the profile.
if [[ -n "$profile_name" ]]; then
  export OS_DIR="${OS_DIR:-$SCRIPT_DIR}"
  # shellcheck source=lib/common.sh
  source "${SCRIPT_DIR}/lib/common.sh"
  # shellcheck source=lib/config/profile.sh
  source "${SCRIPT_DIR}/lib/config/profile.sh"
  # shellcheck source=lib/live-medium.sh
  source "${SCRIPT_DIR}/lib/live-medium.sh"

  validate_profile "$profile_name"
  profile_json="$(load_profile "$profile_name")"
  # Expected control-flow failures (no layout, no disks) exit with the picker's
  # own actionable message — no generic abort footer.
  assignment="$(_install_pick_assignment "$profile_json")" || exit "$?"

  effective_config="$(mktemp "${TMPDIR:-/tmp}/install-effective.XXXXXX.jsonc")"
  assemble_profile_config "$profile_name" "$assignment" > "$effective_config"
  positional_args=("$effective_config")
fi

# Resolve the install's target disks from the config (single .disk, or multi
# os_pool/storage_groups/data_pools) so the wipe only ever touches disks this
# install will use. Mirrors 03-install.sh's config-path default. A missing
# config yields no targets — the wipe no-ops and 03 generates the template.
CONFIG_FILE="${positional_args[0]:-${SCRIPT_DIR}/install.jsonc}"
wipe_targets=()
if [[ -f "$CONFIG_FILE" ]]; then
  mapfile -t wipe_targets < <(wipe_resolve_targets "$CONFIG_FILE")
fi

bash "${SCRIPT_DIR}/01-bootstrap-zfs.sh"
bash "${SCRIPT_DIR}/02-wipe.sh" "${forward_args[@]}" "${wipe_targets[@]}"
bash "${SCRIPT_DIR}/03-install.sh" "${forward_args[@]}" "${positional_args[@]}"
