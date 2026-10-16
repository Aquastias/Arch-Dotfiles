# 08: Contract: make the raw config read lint strict

**What to build:** with every batch migrated, the lint baseline is deleted
and any raw config read outside the Install Config Reader fails outright.
CONTEXT.md (Install Config Reader) describes binding; a new ADR records the
bind + schema-owns-all-defaults decision as extending ADR 0015. Decisions:
candidate #1, Q15–Q18.

**Blocked by:** 04, 05, 06, 07

**Status:** done

- [x] Baseline deleted; lint strict
- [x] CONTEXT.md Install Config Reader entry updated
- [x] ADR recorded (extends 0015)
- [x] Full suite + lints green

## Comments

2026-10-15: Baseline deleted; raw-config-reads.sh strict (`--update` gone,
each read reported as `raw config read: file:line: text`). CONTEXT.md:
Install Config Reader entry (+ Install Default / Guided Launch Preset from
02). ADR 0154 records bind + schema-owns-Install-Defaults + launch presets +
the lint, extending ADR 0015 (cross-linked).

2026-10-15 VM-verified on a7410bd (`--local`): `single/ext4-plain`
(non-ZFS root; no zfs userland) and `data-pools/ext4` (zfs root + ext4 data
pool) install exit 0 + boot OK. Matrix `zfs-single-plain` ran clean through
config/validate/layout/pools/pacstrap/chroot/KDE into the Profiles Runner,
then AUR Vetting aborted vscodium-bin on `trust-adopted` — a false positive
(Icelk maintains since 2021; d04471d is pkgver+sums only). Guided flows not
run: they install vscodium too; pending the allowlist / heuristic decision.

2026-10-16 VM, all install exit 0 + boot OK: `data-pools/mixed` (ext4 +
xfs + btrfs data pools, all mounted at boot) on 9305844; matrix
`zfs-single-plain` (KDE + aquastias + vscodium-bin, allowlisted 71dd721) and
`single/guided` (ISO pinned — see vm-empty-iso-fast-fail) on c977456. Two
upstream breaks found + fixed on the way: linux-lts patch bump vs the archzfs
prebuilt (9305844, ADR 0137 amended) and Plasma 6.8 dropping
plasma-x11-session (c977456, ADR 0053 amended).
