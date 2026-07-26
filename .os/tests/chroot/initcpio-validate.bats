#!/usr/bin/env bats
# Validator-tier tests for the REAL initcpio HOOKS pipeline (ADR 0048, issue
# 03): the active Root Layout Adapter's hook builder (nonzfs_hooks/btrfs_hooks)
# → _initcpio_hooks_line (the chroot generator) → a real /etc/mkinitcpio.conf,
# validated by REAL `mkinitcpio` building to /dev/null.
#
# What this adds over the pure-logic unit tests (chroot-initcpio.bats' kmod
# swap, layout/*-boot.bats' ordering regexes): mkinitcpio's own verdict that
# every hook in the assembled list actually resolves and the config builds — the
# "Hook 'X' cannot be found" class — which no stubbed test can see. mkinitcpio
# does NOT enforce semantic ordering, so the order assertions here (and in the
# adapter unit tests) remain the guard for the modprobe-before-mount class.
#
# Hosts without a given hook's install script (e.g. no archzfs → no `zfs`
# hook) SKIP the build for that adapter, mirroring audit.sh SKIP semantics.

setup() {
  load ../lib/validators
  TEST_DIR="$(mktemp -d)"

  # initcpio.sh runs install_state_load at source time (before its LIB_ONLY
  # guard), so hand it a minimal state file — we only use the pure helpers.
  export STATE="$TEST_DIR/install-state.json"
  cat > "$STATE" <<'JSON'
{"hostname":"h","timezone":"UTC","locale":"en_US.UTF-8",
 "locales":["en_US.UTF-8"],
 "keymap":"us","keymaps":["us"],"kernel":"lts","kernels":["lts"],
 "bootloader":"systemd-boot","filesystem":"zfs","ssh":{"enabled":false},
 "rpool":"rpool","root_cmdline":"root=ZFS=rpool/ROOT/arch",
 "hooks":"base udev autodetect modconf block keyboard zfs filesystems",
 "gpu":[],
 "swap":true,"zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20},
 "esp_count":1,
 "impermanence":{"enabled":false,"dataset":"rpool/persist","mount":"/persist"},
 "persist":{"directories":[],"files":[]}}
JSON

  local l="$BATS_TEST_DIRNAME/../.."
  # Real adapter hook builders (nonzfs_hooks / btrfs_hooks).
  # shellcheck source=../../lib/layout/nonzfs/boot.sh
  source "$l/lib/layout/nonzfs/boot.sh"
  # shellcheck source=../../lib/layout/btrfs/boot.sh
  source "$l/lib/layout/btrfs/boot.sh"
  # Real chroot generator (_initcpio_hooks_line), side effects off.
  INITCPIO_LIB_ONLY=1 source "$l/lib/chroot/initcpio.sh"

  # Resolve modconf→kmod exactly as the generator does on this host.
  [[ -e /usr/lib/initcpio/hooks/kmod ]] && KMOD=true || KMOD=false
  # Fixed conf path (initcpio.sh enables `set -u`; _assemble_conf writes here
  # from inside a command-substitution subshell, so the path — not a global set
  # in the subshell — is what the parent reads).
  CONF="$TEST_DIR/mkinitcpio.conf"
}
teardown() { rm -rf "$TEST_DIR"; }

# Assemble the real mkinitcpio.conf the installer would write for an adapter's
# HOOKS list, echo the HOOKS=(...) line, and leave the conf at $CONF.
_assemble_conf() {  # $1 = adapter HOOKS string
  local line; line="$(_initcpio_hooks_line "$1" "$KMOD")"
  printf 'MODULES=()\nBINARIES=()\nFILES=()\n%s\n' "$line" > "$CONF"
  printf '%s\n' "$line"
}

# ── real mkinitcpio build-validation (SKIP per absent hook) ──────────────────

# Assemble the adapter's HOOKS, skip if the host lacks any of its install
# scripts, else build for real and assert mkinitcpio found every hook.
_build_ok() {  # $1 = adapter HOOKS string
  validators_skip_unless mkinitcpio
  local line; line="$(_assemble_conf "$1")"
  validators_skip_unless_hooks_installable "$line"
  run validators_mkinitcpio_build "$CONF"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "cannot be found" ]]
}

@test "ext4 root HOOKS build clean under mkinitcpio" {
  _build_ok "$(nonzfs_hooks)"
}

@test "encrypted ext4 HOOKS build clean under mkinitcpio" {
  _build_ok "$(nonzfs_hooks encrypted)"
}

# btrfs multi injects the stock `btrfs` hook (installed on any host), so this
# builds for REAL here; the impermanence variant additionally needs the
# project's `btrfs-rollback` hook and SKIPs off an archzfs env.
@test "btrfs multi HOOKS build clean under mkinitcpio" {
  _build_ok "$(btrfs_hooks "" multi)"
}

@test "btrfs single+impermanence HOOKS build clean under mkinitcpio" {
  _build_ok "$(btrfs_hooks "" "" impermanence)"
}

# The zfs adapter builds HOOKS inline in lib/layout/zfs/plan.sh (no standalone
# builder to source), so this mirrors that string verbatim. SKIPs off archzfs
# (no `zfs` install hook); runs for real on an archzfs host/VM.
@test "zfs root HOOKS build clean under mkinitcpio (SKIP without archzfs)" {
  _build_ok "base udev autodetect modconf block keyboard zfs filesystems"
}

# ── generator preserves boot-critical order (modprobe-before-mount class) ─────
# The adapter unit tests (layout/*-boot.bats) own per-filesystem ordering of the
# builder output; mkinitcpio does NOT enforce order, so it cannot. This asserts
# the one thing neither covers: that the chroot generator (_initcpio_hooks_line,
# via the modconf→kmod swap) does not reorder the encrypt/block → filesystems
# pivot end-to-end. The regression gives that invariant teeth.

@test "generator preserves encrypt/block before filesystems end-to-end" {
  local line; line="$(_assemble_conf "$(nonzfs_hooks encrypted)")"
  [[ "$line" =~ block.*encrypt.*filesystems ]]
}

@test "regression: a scrambled generator line (filesystems first) is caught" {
  local line; line="$(_assemble_conf "base filesystems block")"
  [[ ! "$line" =~ block.*filesystems ]]
}
