Status: done

# Dirty-ISO boot-verify VM fixture

## Parent

Follow-up to the ZFS root boot bug fixed in
`fix(installer): Per-pool zpool.cache + zfs_import_dir boot guard`.

## Why

VM smoke tests verify the installer *runs* (sentinel
`===INSTALLER-EXIT-0===`) but `--noreboot` means they never boot the
installed HD system. The original brick — a corrupt `zpool.cache`
baked into the initramfs — passed every VM test and only failed on
real hardware (laptop `chronos`). VMs survived because their live
ISO had no stale `/etc/zfs/zpool.cache`; the laptop's did. We need a
fixture that reproduces the dirty-ISO condition AND asserts the
installed system boots.

## What to build

A new VM fixture + harness capability that, behind an opt-in flag,
power-cycles to the installed disk and confirms it boots.

1. **Dirty-ISO pre-seed.** Before running the installer, the
   fixture's user-data writes garbage to `/etc/zfs/zpool.cache` on
   the live system (reproduces the laptop's dirty ISO).
2. **First-boot serial sentinel (test-only).** After install
   succeeds, the user-data re-imports the pool at a temp altroot and
   drops a oneshot unit into the new root:
   `ExecStart=/bin/sh -c 'echo ===FIRSTBOOT-OK=== >/dev/ttyS0'`,
   `ExecStartPost=/bin/systemctl disable firstboot-ok`. Writing
   straight to `/dev/ttyS0` needs no `console=` cmdline and no
   getty. Export, then emit `===INSTALLER-EXIT-0===` + poweroff as
   today. This injection lives in the test env / seed-generator path
   ONLY — the production installer never ships it.
3. **Harness `--verify-boot` phase.** After the install sentinel,
   eject both cdroms (ISO + seed) via virsh so UEFI boots the ESP
   (systemd-boot removable `BOOTX64.EFI`), restart, re-capture the
   serial console, and wait for `===FIRSTBOOT-OK===` under a boot
   timeout.
4. **Generalize sentinel-watcher.** Add a marker-agnostic wait
   (e.g. `sentinel_watcher_wait_marker LOG MARKER TIMEOUT`) so the
   harness can wait on `===FIRSTBOOT-OK===` as well as the existing
   exit sentinel. Keep the exit-code parser intact.
5. **Dedicated env script.** A single fixture (e.g.
   `testing-single-disk-dirty-cache.sh`) sets `--verify-boot`,
   carries the dirty-cache + first-boot-unit user-data steps, and is
   the only env that runs the boot phase. Other envs unchanged.

## Acceptance criteria

- [x] Fixture pre-seeds a garbage `/etc/zfs/zpool.cache` on the live
      ISO before install (renderer `DIRTY_CACHE`, unit-tested).
- [x] After a successful install, the harness power-cycles to the
      installed disk (cdroms ejected) and the installed system
      reaches `===FIRSTBOOT-OK===` on serial within the boot timeout.
      Verified end-to-end on libvirt/KVM (`FIXTURE_EXIT=0`) — see
      `02-installed-system-silent-on-boot-verify.md` (required the
      forced-export fix; run with `VM_VCPUS=8` so the DKMS source build
      fits the install timeout).
- [x] The first-boot sentinel unit self-disables and is injected
      test-only — a normal (non-fixture) install never contains it
      (renderer `VERIFY_BOOT`, unit-tested incl. default-off).
- [x] `sentinel-watcher` waits on an arbitrary marker; existing
      `INSTALLER-EXIT-N` parsing unchanged (regression-covered in
      `sentinel-watcher.bats`).
- [x] The boot phase is opt-in (`--verify-boot`); the default VM
      suite's runtime/behaviour is unchanged for other fixtures
      (full bats suite still green; knobs default off).
- [x] With the shipped fix in place the fixture passes; reverting BOTH
      the per-pool seeding loop AND `zfs_import_dir` makes it fail
      (proves it guards the real bug class). Wording corrected: the two
      guards are redundant, so reverting EITHER alone still boots —
      reverting BOTH is required to repro the brick.

## Notes

- `zfs_import_dir=/dev/disk/by-id` on the boot cmdline means a bad
  cache cannot brick boot regardless; this fixture also guards that.
- Heavy (~doubles fixture runtime) — keep it out of the fast path.

## Comments

- Item 4 done (TDD): `sentinel_watcher_wait_marker LOG MARKER TIMEOUT` in
  `lib/sentinel-watcher.sh` — fixed-substring match, returns 0/124/2, same
  late-creation + no-mutation contract; 6 new `sentinel-watcher.bats` cases
  (found, timeout, late-arrival, serial CRLF, empty-marker, bad-timeout).
  Remaining: items 1-3, 5 (dirty-cache pre-seed, first-boot unit injection,
  harness `--verify-boot` phase, dedicated env script). Status stays
  `ready-for-agent`.
- Items 1-3, 5 implemented:
  - `lib/seed-generator.sh` — `DIRTY_CACHE`/`VERIFY_BOOT` render flags,
    `SEED_GENERATOR_FIRSTBOOT_MARKER`, `_seed_generator_firstboot_block`;
    harness single-disk path now uses this renderer (duplicate
    `_render_user_data_single` removed). 5 new `seed-generator.bats` cases;
    rendered user-data validated as YAML for both flag combos.
  - `tests/vm/_harness.sh` — `--verify-boot` flag + `DIRTY_CACHE`/`VERIFY_BOOT`/
    `BOOT_TIMEOUT_SEC` knobs, `_eject_cdroms` + `_run_boot_verify` (power-cycle
    to HD, wait marker, exit 125 on boot failure), `_start_console_capture`
    takes a log path.
  - `tests/vm/testing-single-disk-dirty-cache.sh` — dedicated fixture.
- Code-complete; only real-libvirt verification remains (no libvirt/zpool on
  the dev host). Full bats suite green (699), shellcheck clean. Kept
  `ready-for-agent` for an agent/host with libvirt to run + confirm.
- Real-libvirt run attempted on a libvirt-capable host (virsh 12.3, qemu 11,
  /dev/kvm, OVMF). ISO pinned to cached 2026.05.01 (kernel 7.0.3 ↔ archzfs
  7.0; auto-resolver picked today's 2026.06.01 which 404s on archive — release
  day). The run uncovered + fixed TWO blockers, then exposed a third:
  - **Install blocker (fixed, pushed):** `install_state_write` appended `{}`
    onto `load_host_config`'s graceful core-only JSON (rc 1 WITH stdout) →
    `--argjson persist` got two JSON values → install died `EXIT-1` before
    boot-verify. Hits any config whose host_profile has no specific dir (incl.
    repo default). Fixed TDD-style + new `install-state.bats` case (the old
    "host dir absent" test masked it by pointing OS_DIR at a missing dir →
    different empty-stdout branch). Commit
    `fix(installer): Don't concat {} onto core-only host JSON in state write`.
    Install now reaches `EXIT-0` (verified twice).
  - **Harness blocker (fixed):** `_run_boot_verify` started console capture
    BEFORE `virsh start` → `PTY device is not yet assigned`, boot unobserved
    → false 600s timeout. Reordered to start → wait-for-pty → capture (+
    `_wait_for_serial_pty` via `virsh ttyconsole`). Commit
    `fix(vm): Start boot-verify VM before console capture to win PTY race`.
    Capture now attaches (systemd-boot menu visible on serial).
  - **Open (filed as `02-installed-system-silent-on-boot-verify.md`):** with
    both fixes, install → `EXIT-0` → power-cycle → systemd-boot menu →
    kernel handoff → SILENCE for 600s; never reaches `===FIRSTBOOT-OK===`.
    No `console=ttyS0` on the installed cmdline (by design) makes the
    initramfs/ZFS phase invisible, so root cause needs a serial-console boot
    (needs root/guestfish — unavailable in this session). Installed disk
    preserved for that diagnosis.
- AC items 2 and 6 (real boot to FIRSTBOOT-OK + negative control) remain
  unverified, now blocked on `02`. Status stays `ready-for-agent`.
- 2026-06-06: AC 2 re-confirmed on real KVM at HEAD (after the `02`
  force-export fix landed). Dirty-cache fixture, pinned 2026.05.01 ISO,
  8 vCPU/8 GB: `INSTALLER-EXIT-0` → `FIRSTBOOT-OK`, `FIXTURE_EXIT=0`.
- AC 6 (negative control) still open, and its premise needs a correction:
  the two guards are INDEPENDENT and REDUNDANT, so reverting EITHER alone
  does NOT brick. Per-pool seeding (`_chroot_seed_zpool_cache`,
  `lib/chroot.sh`) bakes a VALID cache; `zfs_import_dir=/dev/disk/by-id`
  (`lib/chroot/bootloader-systemd-boot.sh`) makes the initramfs ZFS hook
  ignore the cache entirely (its own comment: "cannot brick boot
  regardless"). To reproduce the original brick the negative control must
  revert BOTH (restore the stale-cache `cp` fallback AND drop
  `zfs_import_dir`), then confirm the fixture fails to reach FIRSTBOOT-OK.
- 2026-06-06: AC 6 DONE. Negative control run on real KVM. Built a
  throwaway local clone with BOTH guards reverted (`cp` stale-cache
  fallback restored + `zfs_import_dir` dropped from both boot entries),
  served it to the VM via `git daemon` on the libvirt bridge (REPO_URL
  override), and ran the dirty-cache fixture. Result: install still
  `INSTALLER-EXIT-0`, but the power-cycle boot BRICKED — never reached
  `FIRSTBOOT-OK`, boot log ends in `Kernel panic - not syncing: Attempted
  to kill init!` (initramfs couldn't import rpool: corrupt cache baked +
  no by-id fallback). `FIXTURE_EXIT=125`. Confirms the fixture guards the
  real bug class. Clone + daemon torn down; real tree/GitHub untouched.
  All 6 ACs now met — issue done.
