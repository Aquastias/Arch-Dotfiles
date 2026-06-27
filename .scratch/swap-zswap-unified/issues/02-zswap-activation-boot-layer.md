# zswap activation (default on) at the boot layer

Status: ready-for-agent

## Parent

`.scratch/swap-zswap-unified/PRD.md`

## What to build

Make compressed swap caching (**zswap**) active by default at boot, with no extra
package. zswap is a kernel feature enabled purely through kernel command-line
parameters appended by both Bootloader Adapters; the disk-backed swap device (ZFS
swap zvol, or swap partition) is created exactly as today.

This slice delivers zswap-on-by-default end-to-end at the boot layer **without any
new UI** — the seeded defaults make it active. The Guided Installer controls for
editing zswap come in a later slice.

Schema (additive — existing `options.swap` / `options.swap_size` unchanged):

- `options.zswap.enabled` — bool, default `true`
- `options.zswap.compressor` — string, default `"zstd"`
- `options.zswap.max_pool_percent` — int, default `20`

No `zswap.zpool` key — modern kernels hardcode `zsmalloc` and dropped the
parameter, so emitting it would be a no-op.

A new **pure module** maps Config State → kernel cmdline fragment:

- swap on **and** zswap on →
  `zswap.enabled=1 zswap.compressor=<compressor> zswap.max_pool_percent=<n>`
- otherwise → empty string.

Both Bootloader Adapters append the fragment: systemd-boot to the `options …`
line of the main **and** fallback entries; GRUB to the default kernel command
line. The module is staged into the chroot lib dir like the other staged libs the
adapters source. The pre-install summary's swap line reflects size + zswap state.
The new keys join the profile's covered fields so Save/Export emit them.

## Acceptance criteria

- [ ] `options.zswap.{enabled,compressor,max_pool_percent}` exist with defaults
      `true` / `zstd` / `20`; existing swap keys and disk-swap creation are
      unchanged.
- [ ] Accessors expose `zswap_enabled`, `zswap_compressor`,
      `zswap_max_pool_percent` from install state.
- [ ] The cmdline module emits the full fragment when swap+zswap are on; reflects
      a custom compressor and percent; returns empty when zswap is off; returns
      empty when swap is off; never emits a `zswap.zpool` token.
- [ ] The cmdline module is staged into the chroot and used by both adapters.
- [ ] systemd-boot main and fallback entries carry the fragment.
- [ ] GRUB default kernel command line carries the fragment.
- [ ] The pre-install summary swap line reflects size and zswap state.
- [ ] The three `options.zswap.*` keys survive a Save/Export/load round-trip; an
      existing profile without them still loads unchanged.
- [ ] Bats cover the cmdline module, accessors, and profile round-trip (prior
      art: pure JSON-contract helper tests; install-config + profile-loader
      tests). Full bats suite green.

## Blocked by

None - can start immediately (parallel to issue 01).
