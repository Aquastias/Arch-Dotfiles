#!/usr/bin/env bash
# tools/pick.sh — Pre-Install Picker (slice 4: review + 4-way + hand-off).
#
# Generates .os/install.jsonc from a chosen host's Install Template plus
# operator-picked mode and target disks, then runs the review/confirm loop.
# When the template pins layout (`.mode`, +`os_pool.topology` for multi),
# the mode prompt is skipped and the pinned topology is honored — disks are
# still always picked (ADR-0029). See ADR-0010, CONTEXT.md → Pre-Install
# Picker.
#
# Four-way prompt keys (after the review block):
#   [i]nstall    — write .os/install.jsonc, then exec install.sh
#   [w]rite only — write .os/install.jsonc and exit 0
#   [e]dit       — re-enter at mode → disks (or disks only when the
#                  template pins mode; host kept; abort+rerun to change host)
#   [a]bort      — exit non-zero, no file written
#
# Deep modules (lib/picker.sh) are pure and bats-tested. The pieces here —
# fzf prompts, the prompt loop, the file write, the exec hand-off — are
# shallow TTY-coupled glue and are validated by running pick.sh on the live
# CD, not by bats.
#
# Picker-time validation is layout-only: `picker_validate_layout` checks the
# mode/disk-count pair before assembly. There is no further config-shape
# check before write — a malformed Install Template can still fail at install
# time. Tightening this would require running `validate_install_context` from
# `lib/config/validation.sh`, which pulls in environment/GPU/persist checks that
# would legitimately fail at picker time on the live CD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/picker.sh
source "$OS_DIR/lib/picker.sh"
# shellcheck source=../lib/live-medium.sh
source "$OS_DIR/lib/live-medium.sh"

HOSTS_DIR="$OS_DIR/hosts"
OUT_FILE="$OS_DIR/install.jsonc"
INSTALL_SH="$OS_DIR/install.sh"

ensure_deps() {
  local need=()
  command -v fzf >/dev/null 2>&1 || need+=(fzf)
  command -v jq  >/dev/null 2>&1 || need+=(jq)
  (( ${#need[@]} == 0 )) && return 0
  if ! pacman -Sy --noconfirm "${need[@]}"; then
    echo "pick.sh: pacman -Sy ${need[*]} failed — live CD needs network" >&2
    exit 1
  fi
}

prompt_host() {
  local hosts=()
  mapfile -t hosts < <(picker_enum_hosts "$HOSTS_DIR")
  if (( ${#hosts[@]} == 0 )); then
    echo "no hosts ship install.template.jsonc — hand-edit $OUT_FILE" >&2
    exit 1
  fi
  printf '%s\n' "${hosts[@]}" | fzf --prompt='host> ' --height=40% --reverse
}

prompt_mode() {
  printf '%s\n' single mirror raidz \
    | fzf --prompt='mode> ' --height=20% --reverse
}

prompt_disks() {
  local live_set disks=()
  # Live medium excluded via the multi-signal Live-Medium Detector
  # (lib/live-medium.sh) — boot-mount parent disk, iso9660, ARCH_* label —
  # robust on label/uuid sources and copytoram boots. Shared with 02-wipe.sh.
  live_set="$(live_medium_disks)"
  mapfile -t disks < <(picker_enum_disks "$live_set")
  if (( ${#disks[@]} == 0 )); then
    echo "no /dev/disk/by-id/* candidates found" >&2
    exit 1
  fi
  printf '%s\n' "${disks[@]}" | fzf \
    --prompt='disks (TAB=multi, ENTER=confirm)> ' --reverse --multi \
    --preview="bash -c 'source \"$OS_DIR/lib/picker.sh\"; picker_format_disk_preview {}'" \
    --preview-window=right,60%
}

# Re-prompt mode + disks until layout validates. Returns via globals
# MODE and DISKS (array). Used on the unpinned path (first entry and
# [e]dit re-entry).
collect_mode_and_disks() {
  while :; do
    MODE="$(prompt_mode)"
    [[ -n "${MODE:-}" ]] || { echo "no mode selected" >&2; exit 1; }
    local picked
    picked="$(prompt_disks)" || { echo "no disks selected" >&2; exit 1; }
    [[ -n "$picked" ]] || { echo "no disks selected" >&2; exit 1; }
    mapfile -t DISKS <<< "$picked"
    if picker_validate_layout "$MODE" "${#DISKS[@]}"; then
      return 0
    fi
    echo "re-pick mode/disks..." >&2
  done
}

# Pinned path: mode is fixed by the template; prompt disks only, until the
# count satisfies the pinned mode/topology. Returns via globals MODE (the
# assemble-mode arg) and DISKS. Used on first entry and [e]dit re-entry.
collect_disks_for_mode() {
  local mode="$1" desc="$2" picked
  echo "layout pinned by template → ${desc}; pick target disks" >&2
  while :; do
    picked="$(prompt_disks)" || { echo "no disks selected" >&2; exit 1; }
    [[ -n "$picked" ]] || { echo "no disks selected" >&2; exit 1; }
    mapfile -t DISKS <<< "$picked"
    if picker_validate_layout "$mode" "${#DISKS[@]}"; then
      MODE="$mode"
      return 0
    fi
    echo "re-pick disks..." >&2
  done
}

main() {
  ensure_deps

  local host template config existing_arg
  host="$(prompt_host)"
  [[ -n "$host" ]] || { echo "no host selected" >&2; exit 1; }

  template="$(picker_load_template "$HOSTS_DIR" "$host")"

  # Optional layout pin (ADR 0029). On a template error (e.g. multi without
  # os_pool.topology) the message is already on stderr — just abort.
  local pin
  pin="$(picker_pin_from_template "$template")" \
    || { echo "pick.sh: invalid layout pin in template" >&2; exit 1; }

  MODE=""
  DISKS=()
  PINNED=0
  PIN_MODE=""
  PIN_DESC=""
  if [[ -n "$pin" ]]; then
    PINNED=1
    local f1 f2
    IFS=$'\t' read -r f1 f2 <<< "$pin"
    if [[ "$f1" == single ]]; then
      PIN_MODE="single"; PIN_DESC="single"
    else
      PIN_MODE="$f2"; PIN_DESC="multi / $f2"
    fi
    collect_disks_for_mode "$PIN_MODE" "$PIN_DESC"
  else
    collect_mode_and_disks
  fi

  while :; do
    config="$(picker_assemble_config "$template" "$host" "$MODE" "${DISKS[@]}")"

    existing_arg=""
    [[ -f "$OUT_FILE" ]] && existing_arg="$OUT_FILE"
    echo
    picker_render_review "$config" "$existing_arg"
    echo
    echo "[i]nstall  [w]rite only  [e]dit  [a]bort"

    local key action
    while :; do
      read -r -n1 -p "> " key || true
      echo
      if action="$(picker_parse_choice "$key")"; then
        break
      fi
      echo "unrecognised — pick one of i/w/e/a" >&2
    done

    case "$action" in
      write_install)
        echo "$config" > "$OUT_FILE"
        echo "wrote $OUT_FILE — handing off to install.sh" >&2
        exec "$INSTALL_SH"
        ;;
      write_only)
        echo "$config" > "$OUT_FILE"
        echo "wrote $OUT_FILE" >&2
        echo "next: run $INSTALL_SH" >&2
        exit 0
        ;;
      edit)
        if (( PINNED )); then
          collect_disks_for_mode "$PIN_MODE" "$PIN_DESC"
        else
          collect_mode_and_disks
        fi
        continue
        ;;
      abort)
        echo "aborted — $OUT_FILE unchanged" >&2
        exit 1
        ;;
    esac
  done
}

main "$@"
