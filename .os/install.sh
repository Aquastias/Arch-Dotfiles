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

With no --profile and no CONFIG_FILE, launches the Guided Installer (an
fzf menu that builds the install interactively).

Options:
  --profile <name>   Host Profile to install (hosts/<name>/). With
                     --print-config, the only profile action wired today.
  --print-config     Validate the --profile against the closed schema,
                     assemble the effective config, print it to stdout, and
                     exit. No disk phase runs (01/02/03 never start).
  --guided <file>    Run the Guided Installer headlessly, replaying menu
                     answers from a key=value file (no fzf, no tty).
  -y, --unattended   Bypass every interactive confirmation prompt (disk
                     selection, "WIPE" confirmation, final "Proceed?").
                     Hostname must be set in the config beforehand.
  -h, --help         Show this help and exit.
EOF
}

# _install_render_assignment <profile_json> <assignment_json>
# Prints the per-group disk mapping (operator-readable) so a multi assignment is
# never implicit (ADR 0037). Caller sends this to stderr — stdout is the JSON.
_install_render_assignment() {
  jq -rn --argjson p "$1" --argjson a "$2" '
    "Disk assignment (per ADR 0037):",
    "  os_pool (\($p.os_pool.pool_name // "rpool"), " +
      "\($p.os_pool.topology // "stripe")): " +
      "\(($a.os_pool // []) | join(" "))",
    ( ($p.storage_groups // []) | to_entries[]
      | "  storage_groups[\(.key)] (\(.value.name), " +
        "\(.value.topology // "stripe")): " +
        "\(($a.storage_groups[.key] // []) | join(" "))" ),
    ( ($p.data_pools // []) | to_entries[]
      | "  data_pools[\(.key)] (\(.value.name), " +
        "\(.value.topology // "stripe")): " +
        "\(($a.data_pools[.key] // []) | join(" "))" )
  '
}

# _install_pick_assignment <profile_json>
# Interactive disk resolution for `--profile`: the profile declares the layout
# (single via .mode/.disk, multi via the pool skeleton + per-group disk_count)
# and the operator picks only the disks (ADR 0036/0037). Emits the assignment
# JSON consumed by assemble_profile_config. A profile that declares no layout
# yet (un-migrated, synthesized) aborts with guidance to use the positional
# config seam meanwhile. Multi: the picked disks are sliced onto every declared
# group by disk_count, in declared order, and the mapping is rendered to stderr.
_install_pick_assignment() {
  local profile_json="$1" mode picked live_set
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
    # Slice the picked disks onto every declared group by disk_count, in
    # declared order (ADR 0037); the per-group min-disk check runs downstream
    # in picker_assign_disks. Render the mapping to stderr so it is explicit.
    local assignment
    assignment="$(picker_build_assignment "$profile_json" "${disks[@]}")" \
      || return 1
    _install_render_assignment "$profile_json" "$assignment" >&2
    printf '%s\n' "$assignment"
  fi
}

forward_args=()
positional_args=()
profile_name=""
print_config=""
guided_replay=""
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
    --guided)
      guided_replay="${2:?--guided requires an answers file}"
      shift 2
      ;;
    --guided=*)
      guided_replay="${1#*=}"
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

# Guided front-end (ADR 0039): bare install.sh — or `--guided <answers>` for a
# headless replay — launches the interactive menu, which assembles a tmpfs
# Effective Config and hands it to the back-end positionally. The typed INSTALL
# in the review screen is the sole consent gate, so the back-end runs
# --unattended (02's WIPE / 03's Proceed don't re-ask; root defaults to 12345 —
# change on first boot; TUI passwords are issue 07).
if [[ -z "$profile_name" && -z "$print_config" ]] \
  && { [[ -n "$guided_replay" ]] || ((${#positional_args[@]} == 0)); }; then
  export OS_DIR="${OS_DIR:-$SCRIPT_DIR}"
  # shellcheck source=lib/common.sh
  source "${SCRIPT_DIR}/lib/common.sh"
  # shellcheck source=lib/guided.sh
  source "${SCRIPT_DIR}/lib/guided.sh"

  [[ -n "$guided_replay" ]] && guided_load_replay "$guided_replay"

  # Stage the no-SOPS password manifest (issue 07): guided_build writes root +
  # per-user passwords here at Proceed; 03-install.sh persists it into
  # install-state under .guided_passwords.*. Exported so the 03 subprocess sees
  # it. Passwords never enter the Effective Config.
  export GUIDED_SECRETS_MANIFEST
  GUIDED_SECRETS_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/guided-secrets.XXXXXX.json")"

  effective_config="$(mktemp "${TMPDIR:-/tmp}/install-effective.XXXXXX.jsonc")"
  guided_build >"$effective_config"
  guided_rc=$?
  # Exit 64 = a terminal action that is NOT install (Save profile / Export
  # config, issue 08): the artifact is written, nothing to install — stop here.
  # Any other non-zero is a cancel/error.
  [[ "$guided_rc" -eq 64 ]] && exit 0
  [[ "$guided_rc" -eq 0 ]] || exit "$guided_rc"
  positional_args=("$effective_config")

  export INSTALL_UNATTENDED=1
  [[ " ${forward_args[*]} " == *" --unattended "* ]] \
    || forward_args+=(--unattended)
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
