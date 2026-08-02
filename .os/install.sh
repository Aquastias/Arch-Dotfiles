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
# Three front-ends over one back-end (ADR 0036/0039), all producing a tmpfs
# Effective Config:
#   ./install.sh --profile <name>          # pick disks against a committed
#                                          # Host Profile, then install
#   ./install.sh /path/to/effective.jsonc  # unattended pre-assembled config
#                                          # (the VM seed's seam)
#   ./install.sh                           # Guided Installer (fzf TUI) when
#                                          # no --profile and no config file
#
# USAGE:
#   ./install.sh --profile <name>          # interactive (picks disks)
#   ./install.sh --profile <name> -y       # unattended (hostname preset)
#   ./install.sh --profile <name> --print-config   # validate + print, no install
#   ./install.sh /path/to/effective.jsonc  # positional config seam
#   ./install.sh                           # Guided Installer
#   ./install.sh --guided answers.txt      # headless guided replay
#
# OPTIONS:
#   --profile <name>   Host Profile under hosts/<name>/ to install.
#   --print-config     Validate --profile + assemble the Effective Config,
#                      print it, and exit (no disk phase runs).
#   --guided <file>    Run the Guided Installer headlessly from an answers file.
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

  # Readable "/dev/sda <size> <model> …" label (field 1) over the by-id path
  # (hidden field 2 — the value kept and previewed via {2}).
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
      # --debug means "inspect/author only", NOT "verbose logging": it skips the
      # install-toolchain preflight (only the front-end tools are ensured, so
      # the menu still opens) and WITHHOLDS the install — the numbered phases
      # below never run, so no disk is touched. Global: honoured by the guided,
      # --profile, and positional-config front-ends alike (ADR 0063).
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

# Minimal preflight: jq parses jsonc on every path (Target Resolver, profile
# load, guided menu), so ensure it before anything else — including the
# --print-config validation below, which is jq-only and touches no disk. The
# Arch ISO ships no jq; install it on the live medium (mirrors lib/secrets.sh's
# age/sops install). The full toolchain check happens further down, only on the
# paths that actually install.
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
preflight_ensure_host_tools jq || exit 1

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

# Full-toolchain preflight: only the paths that actually install reach here
# (--print-config has already exited). The numbered phases shell out to the whole
# partition/format/pacstrap toolchain, and a run wipes disks — so verify every
# host tool now and pacman-install any missing piece before a disk is touched,
# never mid-wipe. fzf is added only when an interactive picker will run: the
# --profile disk picker or the bare guided TUI — not a --guided replay or a
# positional-config install, which drive no menu.
interactive_fzf=""
if [[ -n "$profile_name" ]] \
  || { [[ -z "$guided_replay" ]] && ((${#positional_args[@]} == 0)); }; then
  interactive_fzf=1
fi

# --debug resolver (ADR 0063): decide the preflight tier and whether the
# numbered phases run, purely from the flags — so the "front-end-tools-only,
# never install" guarantee is unit-tested (tests/preflight.bats) without running
# the installer. --debug → the front-end tier (jq, + fzf for an interactive
# front-end) with the install withheld; without it, the full toolchain and a
# real install, exactly as today.
_debug_plan="$(preflight_resolve_plan "${debug_flag:-0}")"
read -r preflight_tier run_install <<<"$_debug_plan"
_pf_arg=()
[[ -n "$interactive_fzf" ]] && _pf_arg=(--interactive)
if [[ "$preflight_tier" == "frontend" ]]; then
  mapfile -t preflight_tools < <(preflight_frontend_tools "${_pf_arg[@]}")
else
  mapfile -t preflight_tools < <(preflight_installer_tools "${_pf_arg[@]}")
fi
preflight_ensure_host_tools "${preflight_tools[@]}" || exit 1

# Quiet the console for the interactive TUI. On the stock Arch ISO the kernel
# writes printk messages straight to the VT at the default console loglevel
# (e.g. `ideapad_acpi ... unexpected charge_types`, a KERN_WARNING). fzf only
# repaints on the next keystroke, so those lines land on top of the menu and it
# looks corrupted. Lower console_loglevel to 1 (only KERN_EMERG breaks through)
# for the life of this session and restore the prior value on exit. Gated on the
# same interactive-fzf condition as the picker/menu above, plus a real terminal
# ([[ -t 1 ]]) so --guided replays, positional installs, and bats runs (no tty)
# never touch kernel.printk. The EXIT trap composes with the ERR trap above.
if [[ -n "$interactive_fzf" && -t 1 ]] \
  && _saved_printk="$(cat /proc/sys/kernel/printk 2>/dev/null)" \
  && [[ -n "$_saved_printk" ]]; then
  trap 'printf "%s\n" "$_saved_printk" >/proc/sys/kernel/printk 2>/dev/null || true' EXIT
  dmesg -n 1 2>/dev/null || true
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

# --debug withholds the install (ADR 0063): the front-end above already ran (the
# guided menu + previews, the --profile picker, Save/Export), but the numbered
# bootstrap/wipe/install phases must never execute, so no disk is touched. This
# is the sole install gate for every front-end — the model is the guided rc-64
# "terminal action that is not install" early-exit above.
if [[ "$run_install" != "yes" ]]; then
  echo "[install.sh] --debug: inspection/authoring only —" \
    "install withheld, no disk touched." >&2
  exit 0
fi

# Pass the config so the bootstrap can skip itself for a pure non-ZFS install
# (ADR 0043): no archzfs repo / zfs module is needed on the live ISO then.
bash "${SCRIPT_DIR}/01-bootstrap-zfs.sh" "$CONFIG_FILE"
bash "${SCRIPT_DIR}/02-wipe.sh" "${forward_args[@]}" "${wipe_targets[@]}"
bash "${SCRIPT_DIR}/03-install.sh" "${forward_args[@]}" "${positional_args[@]}"
