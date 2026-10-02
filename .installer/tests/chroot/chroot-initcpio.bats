#!/usr/bin/env bats
# Tests for _initcpio_hooks_line() in lib/chroot/initcpio.sh.
# Pure function: takes the Root Layout Adapter's HOOKS list (from install-state)
# + whether the modern `kmod` hook is present, emits the HOOKS=(...) line for
# /etc/mkinitcpio.conf, resolving the `modconf` placeholder to `kmod`. The
# adapter owns the hook content; this module is filesystem-blind (ADR 0043).

setup() {
  TEST_DIR="$(mktemp -d)"
  export STATE="$TEST_DIR/install-state.json"
  cat > "$STATE" <<'JSON'
{"hostname":"h","timezone":"UTC","locale":"en_US.UTF-8","locales":["en_US.UTF-8"],
 "keymap":"us","keymaps":["us"],"console_font":"default8x16",
 "kernel":"lts", "kernels": ["lts"],"bootloader":"systemd-boot",
 "root_shell":"/bin/bash",
 "filesystem":"zfs",
 "ssh":{"enabled":false},"rpool":"rpool",
 "root_cmdline":"root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id",
 "hooks":"base udev autodetect modconf block keyboard zfs filesystems",
 "gpu":[],
 "display_manager":"none",
 "swap":true,
 "zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20},
 "esp_count":1,
 "impermanence":{"enabled":false,"dataset":"rpool/persist","mount":"/persist"},
 "persist":{"directories":[],"files":[]}}
JSON
  # Source initcpio.sh in lib-only mode so its side-effect block doesn't run.
  INITCPIO_LIB_ONLY=1 source \
    "$BATS_TEST_DIRNAME/../../lib/chroot/initcpio.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── kmod present: the modconf placeholder resolves to kmod ───────────────────

@test "hooks line: kmod present swaps the modconf placeholder to kmod" {
  run _initcpio_hooks_line \
    "base udev autodetect modconf block keyboard zfs filesystems" true
  [ "$status" -eq 0 ]
  [ "$output" = \
    "HOOKS=(base udev autodetect kmod block keyboard zfs filesystems)" ]
}

# ── kmod absent (older mkinitcpio): modconf is kept verbatim ─────────────────

@test "hooks line: kmod absent keeps modconf" {
  run _initcpio_hooks_line \
    "base udev autodetect modconf block keyboard zfs filesystems" false
  [ "$status" -eq 0 ]
  [ "$output" = \
    "HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)" ]
}

# ── the adapter's list is wrapped verbatim (zfs-rollback preserved) ──────────

@test "hooks line: wraps the adapter list, preserving zfs-rollback" {
  run _initcpio_hooks_line \
    "base udev autodetect modconf block keyboard zfs zfs-rollback filesystems" \
    true
  [ "$status" -eq 0 ]
  [ "$output" = \
"HOOKS=(base udev autodetect kmod block keyboard zfs zfs-rollback filesystems)"\
  ]
}

# ── early KMS (Arch default `kms` hook since mkinitcpio v33) ─────────────────

@test "hooks line: kms goes right after the module hook when wanted" {
  run _initcpio_hooks_line \
    "base udev autodetect modconf block keyboard zfs filesystems" true true
  [ "$output" = \
    "HOOKS=(base udev autodetect kmod kms block keyboard zfs filesystems)" ]
}

@test "hooks line: an adapter's own kms is not duplicated" {
  run _initcpio_hooks_line \
    "base udev autodetect microcode modconf kms block keyboard filesystems fsck" \
    true true
  [ "$output" = \
"HOOKS=(base udev autodetect microcode kmod kms block keyboard filesystems fsck)" ]
}

@test "hooks line: NVIDIA (kms false) strips an adapter's kms" {
  run _initcpio_hooks_line \
    "base udev autodetect microcode modconf kms block keyboard filesystems fsck" \
    true false
  [ "$output" = \
    "HOOKS=(base udev autodetect microcode kmod block keyboard filesystems fsck)" ]
}

@test "wants_kms: in-tree GPUs yes; proprietary NVIDIA no (wiki: MODULES)" {
  run _initcpio_wants_kms amd;          [ "$output" = true ]
  run _initcpio_wants_kms intel;        [ "$output" = true ]
  run _initcpio_wants_kms;              [ "$output" = true ]
  run _initcpio_wants_kms amd nvidia;   [ "$output" = false ]
}

# ── _initcpio_udev_override (pure emitter) ───────────────────────────────────
# Shadows /usr/lib/initcpio/hooks/udev so the initramfs settle is bounded
# instead of the unbounded default — a slow device can't stall boot past the
# cap (ADR 0030, boot-import issue 02).

@test "_initcpio_udev_override: caps the settle at 30s" {
  run _initcpio_udev_override
  [ "$status" -eq 0 ]
  [[ "$output" == *"udevadm settle --timeout=30"* ]]
}

@test "_initcpio_udev_override: keeps the stock trigger pair" {
  # Same coldplug as the stock hook — trigger subsystems then devices — so
  # bounding the settle doesn't regress device discovery.
  run _initcpio_udev_override
  [ "$status" -eq 0 ]
  [[ "$output" == *"udevadm trigger --action=add --type=subsystems"* ]]
  [[ "$output" == *"udevadm trigger --action=add --type=devices"* ]]
}

# ── _initcpio_write_udev_override (thin I/O) ─────────────────────────────────

@test "_initcpio_write_udev_override: shadows the stock udev hook" {
  local root="$BATS_TEST_TMPDIR/root"
  run _initcpio_write_udev_override "$root"
  [ "$status" -eq 0 ]
  # /etc/initcpio/hooks/udev takes precedence over /usr/lib/initcpio/hooks/udev.
  local f="$root/etc/initcpio/hooks/udev"
  [ -f "$f" ]
  grep -q 'udevadm settle --timeout=30' "$f"
}
