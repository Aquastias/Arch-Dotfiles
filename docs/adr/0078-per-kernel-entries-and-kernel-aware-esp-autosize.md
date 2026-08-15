# Per-kernel boot entries and kernel-aware ESP auto-sizing

Status: accepted (amends ADR 0038 — lifts its primary-only entry rule and its
static `esp_size` default; amends ADR 0077 — supersedes its "keep primary-only"
line and makes the efistub secondary-ESP entry concrete)

Every Bootloader Adapter now boots **every selected kernel**, not just the
Primary. The Kernel Selection already lands in install-state as the ordered
`KERNELS` array (element 0 = `KERNEL` = Primary Kernel); the adapters stop
ignoring it. The explicit-entry loaders — `systemd-boot`, `limine`, `efistub` —
iterate `KERNELS` and emit a default entry **and** a fallback entry per kernel,
with per-kbase filenames (`arch-${KBASE}.conf` / `arch-${KBASE}-fallback.conf`,
replacing the hardcoded `arch-zfs.conf`). `grub` (`grub-mkconfig`) and `refind`
(autodetect) already enumerate every installed kernel natively, so they keep
doing that — the only change is pinning the default to the Primary Kernel. All
five loaders default-boot the Primary via their own mechanism (systemd
`default`, `GRUB_DEFAULT`, `limine default_entry`, `refind default_selection`,
efistub `BootOrder`). The Stray Kernel exclusion (ADR 0038) is unchanged: only
Kernel-Selection kernels get entries, so ESP Kernel Sync — entry-driven —
mirrors exactly the selected set and never a stray.

`efistub` stays **raw** (kernel + `initrd=` + cmdline as `efibootmgr`
load-options); UKI/secure-boot remains out of scope and, when needed, becomes
its own cross-loader ADR rather than an efistub-only wart. Because efistub has
no loader binary, its secondary-ESP registration is not the single `--loader`
entry the other loaders use: it re-emits the *same* per-kernel entries against
each secondary disk's ESP. Primary registration and the secondary-ESP loop both
call **one shared emit helper**, keyed off the Bootloader Manifest's
`esp_style` (ADR 0077), so cmdline / initrd / microcode can never drift between
disks and the entry count scales with `KERNELS` automatically.

`esp_size` gains an **`auto`** mode, which becomes the default. Auto-sizing is
an **estimate**, not a measurement — the ESP is partitioned before pacstrap and
mkinitcpio build any initramfs, so it cannot read real file sizes — and it is
**upward-only**, never shrinking below ADR 0038's 2G:

```
need = base(~180M loaders + loader dir + microcode)
     + Σ selected kernels × [ vmlinuz ~16M + default initramfs ~54M
                              + fallback initramfs ~205M
                              + zfs surcharge ~30M  (only when filesystem=zfs) ]
     + transient ~205M   (one fallback temp-then-rename during sync, ADR 0038)
     + one-kernel growth slack ~305M
esp_size(auto) = max( 2G , roundup_256M(need) )
```

`grub` is exempt from the whole budget: it reads `/boot` (ZFS or ext4) directly,
so its ESP holds only the ~15M grub binary and takes a fixed small ESP. The
per-kernel term applies only to the ESP-mirroring loaders (systemd-boot,
efistub, limine, refind), tying the sizing to ADR 0077's loader taxonomy.

A **pre-install ESP budget guard** — the authoring-time twin of ADR 0038's
runtime PreTransaction preflight — computes `need` and, when a numeric
`esp_size` pin is below it, **blocks with an actionable error** surfaced live in
the Guided Kernels / Disks screens (not only at Proceed). A pinned `esp_size` is
never silently rewritten; the operator's disk-layout choice is honoured or
refused loudly, never overridden. The `auto` default computes upward; only an
explicit pin can be too small, and only that path blocks.

Measured worst case (real Arch box, raw layout): ~275M/kernel (16 vmlinuz + 54
default + 205 fallback initramfs); four ZFS kernels with fallbacks + transient +
slack ≈ **1.9G → ~2G**, so the full selectable set lands right at today's floor
and auto-size only pushes *above* 2G when initramfs grow or a fifth kernel is
ever added. The old 1G floor cannot hold the full set — the overflow class that
ADR 0038 was written to prevent.

## Considered options

- **Silently auto-bump a pinned `esp_size`** — rejected: `esp_size` is an
  operator-pinned disk-layout field; auto-size may only *default* it, never
  rewrite an explicit value. Too-small pins block loudly instead.
- **Tight auto-size fitting exactly the selected kernels** — rejected: it throws
  away the growth headroom ADR 0038 added on purpose, re-creating the
  overflow-on-later-`pacman -S linux-zen` brick. Auto-size is therefore
  upward-only from 2G.
- **Measure the built initramfs to size the ESP** — rejected: impossible by
  ordering (the ESP is partitioned before the initramfs exists). The estimate
  is the only pre-partition option; ADR 0038's runtime preflight remains the
  truth-time backstop.
- **UKI / secure-boot for efistub now** — deferred: UKI is a cross-loader
  signing/image concern (systemd-boot boots UKIs too), not an efistub feature.
  Reopen as its own ADR when secure-boot is a concrete requirement.
- **Force explicit per-kernel entries on grub / refind** — rejected: both
  discover installed kernels natively; hand-emitting entries would fight that
  for no benefit. Only pin their default to the Primary.
- **Primary-only fallback under multi-kernel** — rejected (Q6): every kernel
  gets a fallback for a uniform model; the budget/guard covers the ESP cost.

## Consequences

- ADR 0038 amended: its "entries name only the Primary Kernel" rule is lifted;
  its static 2G `esp_size` default becomes `auto` (upward-only). The 1G value
  survives only as the absolute floor the auto budget builds on.
- ADR 0077 amended: its "keep primary-only for now" line is superseded, and its
  efistub `esp_style` secondary-entry note is now the concrete shared emit
  helper.
- `systemd-boot` / `limine` / `efistub` adapters iterate `KERNELS`; entry
  filenames go per-kbase and the `arch-zfs.conf` hardcode is removed. `grub` /
  `refind` change only their default-selection pin.
- ESP Kernel Sync mechanism is unchanged (still entry-driven) but now mirrors
  every selected kernel, since the entries reference them.
- A new pure ESP-budget function is shared by profile-load validation and the
  Guided live Kernels / Disks checks — the single source of the `need` estimate.
- Implementation TODO: pin the real compressed `zfs.ko`-in-initramfs surcharge
  by measurement; ~30M/kernel is the working budget until then.
