#!/usr/bin/env bats
# Tests for the non-ZFS root device resolver (ADR 0043, issue 04) — the pure
# core that maps a non-ZFS root disk's `ESP + [swap] + root` partition layout to
# device paths, applying the LUKS mapper when the root is encrypted. The Root
# Adapter consumes the resolved `root_dev`/`swap_dev` (mkfs/mkswap targets) and
# the `luks_containers` list (what to luksFormat). The resolver does NOT decide
# partition numbering itself — it reads the slots the planner emits, so the
# planner is the single authority and the two can't drift. These tests feed a
# real plan from nonzfs_partition_plan for that reason. Pure: no disk access —
# part_name's bus suffixing is its own concern, stubbed here as `<disk><num>`.

setup() {
  # error() aborts in production; the planner uses it on a too-small root.
  error() { echo "ERROR: $*" >&2; exit 1; }
  export -f error
  # Isolate the resolver's slot→device/crypt logic from part_name's suffixing.
  part_name() { printf '%s%s' "$1" "$2"; }
  export -f part_name
  # shellcheck source=../../lib/layout/nonzfs/plan.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/nonzfs/plan.sh"
  # shellcheck source=../../lib/layout/nonzfs/devices.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/nonzfs/devices.sh"
}

# Helper: extract a key=value field from the emitted plan.
dev_field() { grep -E "^$1=" | cut -d= -f2-; }

# ── tracer: plaintext, with swap → bare partitions off the plan's slots ─────

@test "devices: plaintext+swap resolves bare parts from the plan slots" {
  local plan; plan="$(nonzfs_partition_plan 40960 512 8192)"
  run nonzfs_root_devices /dev/sda "$plan" plain
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dev_field esp_part)"  = "/dev/sda1" ]
  [ "$(printf '%s\n' "$output" | dev_field swap_part)" = "/dev/sda2" ]
  [ "$(printf '%s\n' "$output" | dev_field root_part)" = "/dev/sda3" ]
  # plaintext: the boot/mkfs targets are the bare partitions.
  [ "$(printf '%s\n' "$output" | dev_field root_dev)"  = "/dev/sda3" ]
  [ "$(printf '%s\n' "$output" | dev_field swap_dev)"  = "/dev/sda2" ]
  # nothing to luksFormat when plaintext.
  [ "$(printf '%s\n' "$output" | dev_field luks_containers)" = "" ]
}

# ── encrypted, with swap → root+swap behind the LUKS mappers ────────────────

@test "devices: encrypted+swap resolves mappers and lists both containers" {
  local plan; plan="$(nonzfs_partition_plan 40960 512 8192)"
  run nonzfs_root_devices /dev/sda "$plan" encrypted
  [ "$status" -eq 0 ]
  # the raw partitions are unchanged; the resolved targets are the mappers.
  [ "$(printf '%s\n' "$output" | dev_field root_part)" = "/dev/sda3" ]
  [ "$(printf '%s\n' "$output" | dev_field root_dev)"  = "/dev/mapper/cryptroot" ]
  [ "$(printf '%s\n' "$output" | dev_field swap_dev)"  = "/dev/mapper/cryptswap" ]
  # both partitions are LUKS containers: <part>:<mapper>, root first.
  [ "$(printf '%s\n' "$output" | dev_field luks_containers)" \
      = "/dev/sda3:cryptroot /dev/sda2:cryptswap" ]
}

# ── no swap → plan puts root on slot 2; no swap fields, no swap container ────

@test "devices: encrypted+noswap puts root on part2 with only a root container" {
  local plan; plan="$(nonzfs_partition_plan 40960 512 0)"
  run nonzfs_root_devices /dev/nvme0n1 "$plan" encrypted
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dev_field root_part)" = "/dev/nvme0n12" ]
  [ "$(printf '%s\n' "$output" | dev_field root_dev)"  = "/dev/mapper/cryptroot" ]
  # no swap partition at all.
  [ "$(printf '%s\n' "$output" | dev_field swap_part)" = "" ]
  [ "$(printf '%s\n' "$output" | dev_field swap_dev)"  = "" ]
  # only the root is wrapped — no cryptswap.
  [ "$(printf '%s\n' "$output" | dev_field luks_containers)" \
      = "/dev/nvme0n12:cryptroot" ]
}
