Status: ready-for-agent

# Core impermanence: minimum viable end-to-end

## Parent

`.scratch/impermanence/PRD.md`

## What to build

The tracer-bullet vertical slice that proves the whole impermanence stack works end-to-end on a single-disk install. After this slice, an operator who sets `options.impermanence.enabled=true` in `install.jsonc` and runs the installer ends up with a system that boots, persists all Curated Persist Defaults across reboot, and reverts non-persisted edits to the Rollback Datasets on every boot.

Scope of this slice:

- Add `options.impermanence` to the Install Config schema as an object with `enabled` (default `false`), `dataset` (default `rpool/persist`), and `mount` (default `/persist`). Update the example skeleton in `install.jsonc` so operators can discover the option.
- Parse the new option in the config layer. Persist Extensions schema (`persist.directories`/`persist.files` in Host Config) is *out of scope* for this slice — it's slice 2.
- Validate at install time that the Persist Dataset lives on the same pool as `rpool/ROOT/arch`. Other validation rules are deferred to slice 2.
- When enabled, create the Persist Dataset and the five Rollback Datasets (`rpool/ROOT/etc`, `rpool/ROOT/root`, `rpool/ROOT/opt`, `rpool/ROOT/srv`, `rpool/ROOT/usrlocal`) with appropriate `mountpoint` and `canmount` properties. New helper in the ZFS pools library; invoked by the single-disk layout module. The multi-disk module can stay untouched in this slice — the multi-disk fixture is slice 6.
- Generate the Bootstrap Mount pair under `/usr/lib/`: a tmpfiles snippet that creates `/etc/systemd/system/` and `/etc/tmpfiles.d/` as placeholders, and two systemd `.mount` units that bind `/persist/etc/systemd/system` and `/persist/etc/tmpfiles.d` over them. Wire them into `local-fs.target` via the standard `*.wants/` symlink approach. The bootstrap files live in `/usr/lib/` precisely because `/usr/lib/` is on the non-rolled-back `rpool/ROOT/arch` and therefore survives without snapshot manipulation.
- Generate Curated Persist Defaults' `.mount` units and their tmpfiles snippet under `/usr/lib/systemd/system/` and `/usr/lib/tmpfiles.d/`. Source the curated list from a `CURATED_DIRS` + `CURATED_FILES` pair of bash arrays at the top of the new Chroot Configuration Module — this is the single source of truth that the runtime tool will reuse in later slices. The list per PRD: files = `/etc/machine-id`, `/etc/hostname`, `/etc/locale.conf`, `/etc/vconsole.conf`, `/etc/adjtime`, `/etc/fstab`; directories = `/etc/ssh`, `/etc/secrets`, `/etc/NetworkManager/system-connections`, `/etc/sudoers.d`, `/etc/pacman.d`, `/root`.
- Move (not copy) each curated path's content from its live location onto the Persist Dataset before snapshotting. The point of the move is that the resulting `@blank` snapshot contains no secrets — host keys and the Machine Age Key are not baked into the snapshot.
- Take the `@blank` snapshot on every Rollback Dataset.
- Write the curated-defaults manifest at `/usr/lib/impermanence/defaults.manifest` (sorted list of paths) so the runtime tool's `apply-defaults` verb (slice 5) can diff against it later.
- Generate the mkinitcpio Rollback Hook pair (`install` + runtime). The hook iterates the Rollback Datasets, verifies each `@blank` exists, then runs `zfs rollback -r <ds>@blank`. If any `@blank` is missing, fail closed: drop to an interactive emergency shell with a clear message naming the missing snapshot. The dataset list is hardcoded into the runtime hook by the installer at generation time (no kernel cmdline parameter).
- Update the initcpio chroot module to insert the new hook into `HOOKS=` between the existing `zfs` and `filesystems` hooks when impermanence is enabled. Regenerate the initramfs via `mkinitcpio -P` in the same module as before.
- Slot invocation of the new Chroot Configuration Module as the last step in `lib/chroot/configure.sh`, after program installation.
- Persist Mount units must order `After=systemd-tmpfiles-setup.service Before=local-fs.target` with `RequiredBy=local-fs.target` so the boot fails closed if any persist mount fails.
- Unit tests in `tests/chroot-impermanence.bats` for the new chroot module, mocking `zfs`/`zpool` like `tests/chroot-fstab.bats` and `tests/zfs-pools.bats` already do. Assert on: which datasets are created, which unit files are generated, contents of the tmpfiles snippets, the move semantics (curated paths absent from the source location after the module runs, present on the Persist Dataset), and which snapshots are taken.
- VM integration fixture `tests/vm/testing-single-disk-impermanent.sh` following the existing fixture pattern. Verify post-install: all five Rollback Datasets exist with `@blank` snapshots; `/persist` is mounted; `systemctl list-units 'persist-*.mount'` shows the curated units active; an arbitrary edit to a non-persisted path (e.g. write `/etc/touch-me`) vanishes after reboot; the SSH host key is identical before and after reboot.
- When `options.impermanence.enabled=false` (the default), every behavior described above is a no-op — no datasets created, no hook inserted, no unit files written. The existing install flow is byte-for-byte unchanged.

Out of scope for this slice (deferred):

- Persist Extensions schema and validation → slice 2
- Pacman Resnapshot Hook → slice 3
- Runtime tool → slices 4, 5
- Multi-disk fixture → slice 6
- SOPS / encryption fixtures → slices 7, 8
- README chapter → not a slice (separate doc task)

## Acceptance criteria

- [ ] `install.jsonc` has the `options.impermanence` object with sensible defaults; `enabled=false` is the shipped default
- [ ] With `enabled=false`, the existing install flow is unchanged (no new datasets, no unit files, no initramfs changes, no validation differences)
- [ ] With `enabled=true`, the installer creates five Rollback Datasets (`rpool/ROOT/{etc,root,opt,srv,usrlocal}`) plus the Persist Dataset
- [ ] Validation aborts the install if `options.impermanence.dataset` is not on the same pool as `rpool/ROOT/arch`
- [ ] All Curated Persist Defaults are bind-mounted from `/persist` after install
- [ ] The Curated Persist Defaults bash arrays live at the top of the new Chroot Configuration Module (single source of truth)
- [ ] `/usr/lib/impermanence/defaults.manifest` is written by the installer with the sorted curated list
- [ ] `@blank` snapshots exist on every Rollback Dataset post-install and contain no curated-default data (snapshot is genuinely blank)
- [ ] mkinitcpio HOOKS line contains the new rollback hook between `zfs` and `filesystems`
- [ ] Booting with `@blank` missing on any Rollback Dataset drops to emergency shell with a clear error message
- [ ] Booting with `/persist` failing to mount drops to emergency (via the bootstrap mount's `RequiredBy=local-fs.target`)
- [ ] `tests/chroot-impermanence.bats` covers dataset creation, unit-file generation, tmpfiles content, move semantics, and snapshot calls (all `zfs` invocations mocked)
- [ ] `tests/vm/testing-single-disk-impermanent.sh` provisions an impermanent single-disk VM, reboots, and verifies: SSH host key stable across reboot; an unpersisted `/etc/touch-me` write disappears after reboot; all curated persist mounts are active

## Blocked by

None - can start immediately.
