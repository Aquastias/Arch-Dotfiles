# Unified swap control with zswap on by default

Swap is configured as one decision, and compressed swap caching (zswap) is
enabled by default. The two former Guided Installer rows (`swap` toggle +
`swap size`) collapse into a single **swap** row that drills into a
`swapedit` sub-screen, and a new additive `options.zswap.*` block turns on
zswap through kernel command-line parameters — no extra package, no change
to disk-swap creation.

Builds on ADR 0039 (Guided Installer), ADR 0042 (persistent single-fzf
controller), and ADR 0040 (Filesystem Adapter axis). Touches both
Bootloader Adapters.

## Considered Options

- **(a)** Model swap as an `off / normal / zswap` mode enum — rejected. It
  synthesizes a field with no schema backing that needs translation on
  every read/write, and fights the existing bool-per-setting shape.
- **(b)** Add zram (a standalone compressed-RAM swap device) — rejected as
  a different feature; this decision is zswap, a compressed cache *in front
  of* disk-backed swap.
- **(c)** Two independent bools (`options.swap`, `options.zswap.enabled`)
  plus a `swapedit` drill-in, zswap on by default — chosen.

## Decision

Schema is additive — existing profiles keep working with no migration:

- `options.swap` — bool, default `true` (unchanged).
- `options.swap_size` — string, default `"auto"` (RAM×2 sizing unchanged).
- `options.zswap.enabled` — bool, default `true`.
- `options.zswap.compressor` — string, default `"zstd"`.
- `options.zswap.max_pool_percent` — int, default `20`.

No `zswap.zpool` key: modern kernels hardcode `zsmalloc` and dropped the
`z3fold`/`zbud` allocators, so the parameter is a no-op and is omitted from
both schema and cmdline.

Guided Installer: the **Disks** category shows one `swap` row (all
filesystems + single-disk layouts); the old `swap size` row is gone.
Entering it navigates to a `swapedit` screen (data-pools drill-in
convention) whose rows appear only when meaningful — `size`/`zswap` when
swap is on, `compressor`/`max pool %` when zswap is on. The row's one-line
value summarizes the whole decision: `off`, `auto · zswap zstd`,
`8G · no zswap`. Edits flow through Config State, so undo/redo/reset cover
them for free.

Activation is kernel-cmdline only, via a pure, bootloader-agnostic module
`zswap_cmdline_params` (`lib/boot/zswap.sh`) that reads the config JSON and
returns `zswap.enabled=1 zswap.compressor=<c> zswap.max_pool_percent=<n>`
when both swap and zswap are enabled, else the empty string. It is staged
into the chroot lib dir and consumed by both Bootloader Adapters — the
systemd-boot adapter appends the fragment to the `options` line of the main
and fallback entries; the GRUB adapter appends it to
`GRUB_CMDLINE_LINUX_DEFAULT`. Emitting it only when swap *and* zswap are on
guarantees a zswap cmdline never points at a non-existent swap device.

## Consequences

- Disk-swap creation (ZFS swap zvol; single/ext4/xfs swap partition) is
  untouched — zswap layers on top of whatever device is created.
- zswap adds zero install footprint (a kernel feature, not a package).
- The pre-install summary's swap line reflects size and zswap state (e.g.
  `Swap: 8G · zswap (zstd)`).
- The three `options.zswap.*` keys are covered by Save/Export round-trip.
- Hibernation / `resume=` is still not wired; the RAM×2 sizing rationale
  that cited it remains unrealized (out of scope here).
- Live fzf render and the on-target cmdline
  (`/proc/cmdline`, `/sys/module/zswap/parameters/enabled`) stay TTY/VM-
  gated, matching the persistent-fzf controller's verification boundary.
