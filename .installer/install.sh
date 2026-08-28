#!/usr/bin/env bash
# =============================================================================
# install.sh — single entry point for the Arch Linux ZFS installer
# =============================================================================
# Runs three numbered scripts in order (each still individually runnable for
# debugging): 01-bootstrap-zfs.sh (archzfs + ZFS modules on the live ISO),
# 02-wipe.sh (only the install's target disks, resolved from config), then
# 03-install.sh (partition, pacstrap, configure, run profiles).
#
# Three front-ends over one back-end (ADR 0036/0039), all producing a tmpfs
# Effective Config:
#   ./install.sh --profile <name>          # pick disks vs a committed profile
#   ./install.sh /path/to/effective.jsonc  # unattended pre-assembled (VM seed)
#   ./install.sh                           # Guided Installer (fzf TUI)
#
# Recognised flags are stripped here and re-emitted to the numbered scripts; an
# optional positional arg forwards to 03 as the config. See usage() / --help.
# =============================================================================

set -Eeuo pipefail
_install_on_err() {
  # Only the top-level shell reports; `set -E` fires this inside command subs
  # too, which would double-print the same abort.
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
  --profile <name>   Host Profile to install (hosts/<name>/): validate it,
                     pick disks, assemble the effective config, then install.
  --print-config     Validate the --profile against the closed schema,
                     assemble the effective config, print it to stdout, and
                     exit. No disk phase runs (01/02/03 never start).
  --guided <file>    Run the Guided Installer headlessly, replaying menu
                     answers from a key=value file (no fzf, no tty).
  --debug            Inspect/author only: skip the install-toolchain preflight
                     (ensure just the front-end tools jq + fzf) and WITHHOLD the
                     install — the numbered phases never run, so no disk is
                     touched. The menu, previews, --profile picker, and
                     Save/Export still work. NOT verbose logging.
  -y, --unattended   Bypass every interactive confirmation prompt (disk
                     selection, "WIPE" confirmation, final "Proceed?").
                     Hostname must be set in the config beforehand.
  -h, --help         Show this help and exit.
EOF
}

# _install_render_assignment <profile_json> <assignment_json> — print the
# per-group disk mapping so a multi assignment is never implicit (ADR 0037).
# Caller sends this to stderr; stdout is the JSON.
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

# _install_pick_assignment <profile_json> — interactive disk resolution for
# `--profile`: the profile declares the layout, the operator picks only disks
# (ADR 0036/0037). Emits the assignment JSON for assemble_profile_config. A
# profile with no layout yet aborts with guidance to use the positional config
# seam. Multi slices the picked disks onto each declared group by disk_count, in
# declared order (mapping rendered to stderr).
_install_pick_assignment() {
  local profile_json="$1" mode picked live_set p
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

  # Readable "/dev/sda <size> <model>" label (field 1) over the by-id path
  # (hidden field 2 — kept and previewed via {2}).
  picked="$(
    for p in "${candidates[@]}"; do
      printf '%s\t%s\n' "$(picker_disk_label "$p")" "$p"
    done | fzf --multi --reverse \
      --prompt='disks (TAB=multi, ENTER=confirm)> ' \
      --delimiter='\t' --with-nth=1 \
      --preview="bash -c 'source \"$OS_DIR/lib/picker.sh\"; \
        picker_format_disk_preview {2}'" \
      --preview-window=right,60%)" \
    || { echo "[install.sh] no disks selected" >&2; return 1; }
  [[ -n "$picked" ]] || { echo "[install.sh] no disks selected" >&2; return 1; }
  mapfile -t disks < <(printf '%s\n' "$picked" \
    | while IFS=$'\t' read -r _label path; do printf '%s\n' "$path"; done)

  if [[ "$mode" == single ]]; then
    picker_validate_layout single "${#disks[@]}" || return 1
    jq -n --arg d "${disks[0]}" '{mode:"single", disk:$d}'
  else
    # Slice picked disks onto each group by disk_count, declared order (ADR
    # 0037); per-group min-disk check runs downstream in picker_assign_disks.
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
debug_flag=""
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
    --debug)
      # --debug = inspect/author only, NOT verbose logging: skip the install
      # toolchain preflight (front-end tools only, menu still opens) and
      # WITHHOLD the install (numbered phases never run). Honoured by all three
      # front-ends (ADR 0063).
      debug_flag=1
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

# The config the operator passed on the CLI, captured before --profile/guided
# reassign the arg to their tmpfs Effective Config. Used only to reject a
# committed manual layout below — must stay empty on every assembled path.
cli_positional="${positional_args[0]:-}"

# Minimal preflight: jq parses jsonc on every path, so ensure it first —
# including --print-config below (jq-only, no disk). The Arch ISO ships no jq;
# install it on the live medium. Full toolchain check happens further down, only
# on paths that actually install.
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
preflight_ensure_host_tools jq || exit 1

# --print-config: validate the profile, assemble the effective config, print to
# stdout, exit — before any disk phase (01/02/03 never start), so a typo'd key
# aborts with its path first (ADR 0036). OS_DIR honours an existing value
# (tests), else this dir.
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

# Full-toolchain preflight: only install paths reach here (--print-config
# exited). A run wipes disks, so verify every host tool and pacman-install any
# missing piece now, never mid-wipe. fzf added only when an interactive picker
# runs (the --profile picker or bare guided TUI), not a replay or positional
# install.
interactive_fzf=""
if [[ -n "$profile_name" ]] \
  || { [[ -z "$guided_replay" ]] && ((${#positional_args[@]} == 0)); }; then
  interactive_fzf=1
fi

# --debug resolver (ADR 0063): decide the preflight tier and whether the phases
# run, purely from the flags, so the "front-end-only, never install" guarantee
# is unit-tested (tests/preflight.bats). --debug → front-end tier + install
# withheld; else full toolchain + real install.
_debug_plan="$(preflight_resolve_plan "${debug_flag:-0}")"
read -r preflight_tier run_install <<<"$_debug_plan"
# Signal inspect-only mode to guided subprocesses (ADR 0063): a --debug run
# never touches a disk, so disk-touching menu actions (Manual Partitioning
# cfdisk hand-off) go inert. Exported so guided-fzf-entry.sh binds see it.
export INSTALL_DEBUG=0
[[ "$run_install" == "yes" ]] || INSTALL_DEBUG=1
_pf_arg=()
[[ -n "$interactive_fzf" ]] && _pf_arg=(--interactive)
if [[ "$preflight_tier" == "frontend" ]]; then
  mapfile -t preflight_tools < <(preflight_frontend_tools "${_pf_arg[@]}")
else
  mapfile -t preflight_tools < <(preflight_installer_tools "${_pf_arg[@]}")
fi
preflight_ensure_host_tools "${preflight_tools[@]}" || exit 1

# Quiet the console for the TUI: the Arch ISO writes printk messages to the VT,
# and fzf only repaints on keystroke, so they corrupt the menu. Lower
# console_loglevel to 1 for this session, restore on exit. Gated on the same
# interactive-fzf condition plus a real terminal ([[ -t 1 ]]) so replays,
# positional installs, and bats runs (no tty) never touch kernel.printk.
if [[ -n "$interactive_fzf" && -t 1 ]] \
  && _saved_printk="$(cat /proc/sys/kernel/printk 2>/dev/null)" \
  && [[ -n "$_saved_printk" ]]; then
  trap 'printf "%s\n" "$_saved_printk" >/proc/sys/kernel/printk 2>/dev/null || true' EXIT
  dmesg -n 1 2>/dev/null || true
fi

# Interactive --profile front-end: validate the profile, pick disks, assemble
# the effective config in tmpfs (never committed — ADR 0036), hand it to the
# back-end positionally. The picker resolves only disks; layout/identity come
# from the profile.
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
  # Expected failures (no layout, no disks) exit with the picker's own message,
  # no generic abort footer.
  assignment="$(_install_pick_assignment "$profile_json")" || exit "$?"

  effective_config="$(mktemp "${TMPDIR:-/tmp}/install-effective.XXXXXX.jsonc")"
  assemble_profile_config "$profile_name" "$assignment" > "$effective_config"
  positional_args=("$effective_config")
fi

# Guided front-end (ADR 0039): bare install.sh, or `--guided <answers>` for a
# headless replay, launches the menu, which assembles a tmpfs Effective Config
# and hands it to the back-end positionally. The typed INSTALL in the review
# screen is the sole consent gate, so the back-end runs --unattended (02/03
# don't re-ask; root defaults to 12345 — change on first boot).
if [[ -z "$profile_name" && -z "$print_config" ]] \
  && { [[ -n "$guided_replay" ]] || ((${#positional_args[@]} == 0)); }; then
  export OS_DIR="${OS_DIR:-$SCRIPT_DIR}"
  # shellcheck source=lib/common.sh
  source "${SCRIPT_DIR}/lib/common.sh"
  # shellcheck source=lib/guided.sh
  source "${SCRIPT_DIR}/lib/guided.sh"

  [[ -n "$guided_replay" ]] && guided_load_replay "$guided_replay"

  # Stage the no-SOPS password manifest: guided_build writes root + per-user
  # passwords here at Proceed; 03 persists them into install-state under
  # .guided_passwords.*. Exported for the 03 subprocess. Never in the config.
  export GUIDED_SECRETS_MANIFEST
  GUIDED_SECRETS_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/guided-secrets.XXXXXX.json")"

  effective_config="$(mktemp "${TMPDIR:-/tmp}/install-effective.XXXXXX.jsonc")"
  guided_build >"$effective_config"
  guided_rc=$?
  # Exit 64 = a terminal action that is NOT install (Save/Export): artifact
  # written, nothing to install. Any other non-zero is a cancel/error.
  [[ "$guided_rc" -eq 64 ]] && exit 0
  [[ "$guided_rc" -eq 0 ]] || exit "$guided_rc"
  positional_args=("$effective_config")

  export INSTALL_UNATTENDED=1
  [[ " ${forward_args[*]} " == *" --unattended "* ]] \
    || forward_args+=(--unattended)
fi

# Resolve target disks from the config so the wipe only touches disks this
# install uses. Mirrors 03's config-path default. A missing config yields no
# targets — the wipe no-ops and 03 generates the template.
CONFIG_FILE="${positional_args[0]:-${SCRIPT_DIR}/install.jsonc}"

# Manual Partitioning is Guided-only (ADR 0073): a hand-drawn table is not
# reproducible, so an unattended pre-assembled config may not carry it. The
# guided Proceed path is unaffected (cli_positional empty there); only a
# CLI-passed file is rejected.
if [[ -n "$cli_positional" && -f "$cli_positional" \
      && "$(jsonc_read "$cli_positional" '.disk_config.kind // "auto"')" \
         == "manual" ]]; then
  echo "[install.sh] $cli_positional sets disk_config.kind=manual, which is" \
    "Guided-Installer-only (ADR 0073)." >&2
  echo "             Run the guided installer for a manual layout." >&2
  exit 1
fi

wipe_targets=()
if [[ -f "$CONFIG_FILE" ]]; then
  mapfile -t wipe_targets < <(wipe_resolve_targets "$CONFIG_FILE")
fi

# --debug withholds the install (ADR 0063): the front-end already ran, but the
# numbered phases must never execute, so no disk is touched. The sole install
# gate for every front-end, modelled on the guided rc-64 early-exit above.
if [[ "$run_install" != "yes" ]]; then
  echo "[install.sh] --debug: inspection/authoring only —" \
    "install withheld, no disk touched." >&2
  exit 0
fi

# Pass the config so bootstrap can skip itself for a pure non-ZFS install (ADR
# 0043): no archzfs repo / zfs module needed on the live ISO then.
bash "${SCRIPT_DIR}/01-bootstrap-zfs.sh" "$CONFIG_FILE"
bash "${SCRIPT_DIR}/02-wipe.sh" "${forward_args[@]}" "${wipe_targets[@]}"
bash "${SCRIPT_DIR}/03-install.sh" "${forward_args[@]}" "${positional_args[@]}"
