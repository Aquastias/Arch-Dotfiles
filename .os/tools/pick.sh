#!/usr/bin/env bash
# tools/pick.sh — Pre-Install Picker (slice 2: fzf + disk preview, single-disk).
#
# Generates .os/install.jsonc from a chosen host's Install Template plus
# operator-picked target disk. See ADR-0010, CONTEXT.md → Pre-Install Picker.
#
# Slice 2 scope: fzf single-select for hosts + disks, lsblk/smartctl preview
# pane, single-disk only, no review screen, no install hand-off.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/picker.sh
source "$OS_DIR/lib/picker.sh"

HOSTS_DIR="$OS_DIR/hosts"
OUT_FILE="$OS_DIR/install.jsonc"

# Self-install fzf + jq via pacman. Fails loudly on no-network live CDs —
# same constraint that gates pacstrap, so the operator sees the right error.
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

# Resolve the live medium whole-disk path. Empty if not on a live CD.
resolve_live_dev() {
  local part_dev part_base disk_base
  if [[ -d /run/archiso/bootmnt ]]; then
    part_dev="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  fi
  if [[ -z "${part_dev:-}" ]]; then
    part_dev="$(blkid -L ARCH_* 2>/dev/null | head -n1 || true)"
  fi
  [[ -z "${part_dev:-}" ]] && return 0
  part_base="$(basename "$part_dev")"
  disk_base="$(lsblk -no PKNAME "/dev/$part_base" 2>/dev/null | head -n1)"
  [[ -n "$disk_base" ]] && echo "/dev/$disk_base"
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

prompt_disk() {
  local live_dev disks=()
  live_dev="$(resolve_live_dev)"
  mapfile -t disks < <(picker_enum_disks "$live_dev")
  if (( ${#disks[@]} == 0 )); then
    echo "no /dev/disk/by-id/* candidates found" >&2
    exit 1
  fi
  printf '%s\n' "${disks[@]}" | fzf \
    --prompt='disk> ' --reverse \
    --preview="bash -c 'source \"$OS_DIR/lib/picker.sh\"; picker_format_disk_preview {}'" \
    --preview-window=right,60%
}

main() {
  ensure_deps

  local host disk template config
  host="$(prompt_host)"
  [[ -n "$host" ]] || { echo "no host selected" >&2; exit 1; }
  disk="$(prompt_disk)"
  [[ -n "$disk" ]] || { echo "no disk selected" >&2; exit 1; }

  if ! picker_validate_layout single 1; then
    exit 1
  fi

  template="$(picker_load_template "$HOSTS_DIR" "$host")"
  config="$(picker_assemble_config "$template" "$host" single "$disk")"

  echo "$config" > "$OUT_FILE"
  echo "wrote $OUT_FILE" >&2
  echo "next: run $OS_DIR/install.sh" >&2
}

main "$@"
