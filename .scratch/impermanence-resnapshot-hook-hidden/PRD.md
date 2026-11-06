# Pacman Resnapshot Hook never runs on Impermanence installs

Status: done

## Problem

`/etc/pacman.d` is a Curated Persist Default: `_impermanence_apply_curated`
moves it onto the Persist Dataset and a bind mount restores it at boot. The
`impermanence_boot_hooks_write_resnapshot_hook` step runs *after* that move
and writes `zz-impermanence-resnapshot.hook` into the root's own
`/etc/pacman.d/hooks`, which the bind mount hides. So the Pacman Resnapshot
Hook never runs: `@blank` is never refreshed, package changes to
non-persisted `/etc` paths are lost at every reboot, and no Rollback Dataset
gets an Update Snapshot (ADR 0166 `keep-blank`).

Found in the interrupted-update VM runs (2026-11-06,
`.scratch/interrupted-kernel-upgrade/repro.md`): the live
`/etc/pacman.d/hooks` (from `/persist`) lacks the hook; `@blank` of
`rpool/ROOT/etc` holds it; the resnapshot helper never logs.

The bats suite asserts the hidden path
(`$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook`).

## Fix

- Write the hook where `/etc/pacman.d` lives at runtime: write it before
  the curated move, so it moves onto the Persist Dataset with the rest.
- Retrofit existing Impermanence hosts (`tools/harden-boot.sh`): install the
  hook into the live `/etc/pacman.d/hooks` when missing.
- Tests assert the hook ends up on the Persist Dataset.
- VM check: after a pacman transaction on an Impermanence VM, `@blank` is
  re-taken and the Rollback Datasets carry the transaction's `@update-*`.

## Comments

- Fixed and VM-verified (see `.scratch/interrupted-kernel-upgrade/repro.md`):
  the hook step runs before the curated move; the retrofit restores a
  missing hook on existing hosts.
