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
 "keymap":"us","keymaps":["us"],
 "kernel":"lts", "kernels": ["lts"],"bootloader":"systemd-boot",
 "ssh":{"enabled":false},"rpool":"rpool",
 "root_cmdline":"root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id",
 "hooks":"base udev autodetect modconf block keyboard zfs filesystems",
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
