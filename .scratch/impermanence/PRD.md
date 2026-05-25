Status: done

# PRD: Impermanence

## Problem Statement

The installer produces a system whose `/etc`, `/root`, `/opt`, `/srv`, and `/usr/local` accumulate state indefinitely. Hand-edits, abandoned config files, half-installed services, stale credentials, and forgotten experiments build up across the system's lifetime with no mechanism for surfacing them. Operators who value declarative, auditable system state — the kind NixOS achieves via `/nix/store` indirection — have no way to opt into a "reset on every boot" model on Arch. The few system-identity files that *must* survive (machine-id, SSH host keys, Machine Age Key, NetworkManager connections) have no obvious home; persisting them ad-hoc is error-prone and undocumented.

## Solution

Add an optional, install-time Impermanence feature: ZFS dataset rollback on every boot, scoped to the specific datasets where ephemeral system state accumulates. When enabled, the installer splits `/etc`, `/root`, `/opt`, `/srv`, `/usr/local` into dedicated Rollback Datasets, takes a Blank Snapshot of each at the end of the chroot phase, and installs a mkinitcpio Rollback Hook that reverts them on every boot. Persistent state lives on a new Persist Dataset (default `rpool/persist`, mounted at `/persist`), bind-mounted into rolled-back paths via systemd `.mount` units. The installer ships a Curated Persist Defaults list covering system-identity files that would break if lost. Operators declare additional persist paths in their host config; a runtime tool (`os impermanence`) manages extensions after install. A pacman post-transaction hook re-snapshots `@blank` after every transaction so package updates survive across reboots.

Impermanence is fully optional; the installer behaves exactly as before when `options.impermanence.enabled=false` (the default). The feature is install-time only — toggling later requires a re-install.

## User Stories

### Configuration and install

1. As an operator, I want to enable Impermanence with a single flag in `install.jsonc`, so that opting in is one deliberate choice.
2. As an operator, I want to configure the Persist Dataset name and mount point, so that I can match my naming conventions.
3. As an operator, I want Impermanence to be off by default, so that existing install flows are unchanged.
4. As an operator, I want a sensible curated list of system-identity paths persisted automatically, so that I don't have to enumerate machine-id, SSH host keys, hostname, locale, etc. myself.
5. As an operator, I want to declare additional persist paths in `hosts/<hostname>/config.jsonc`, so that machine-specific state survives across reboots.
6. As an operator, I want to declare shared persist paths in `hosts/core/config.jsonc`, so that a fleet of similar hosts doesn't duplicate the same declarations.
7. As an operator, I want persist paths deep-merged across Host Core and Host Config, so that the merge semantics match `sysctl` and `packages`.
8. As an operator, I want to separately declare `persist.directories` and `persist.files`, so that the installer can emit the correct tmpfiles type without ambiguity.
9. As an operator, I want the installer to validate my persist paths at install time, so that misconfiguration fails fast instead of breaking the first boot.
10. As an operator, I want clear warnings for redundant persist declarations (paths under already-persistent datasets, paths already in curated defaults), so that I don't accumulate dead config.

### Boot-time behavior

11. As an operator, I want the system to boot impermanent from boot 1 after install, so that there's no separate "activate impermanence" step.
12. As an operator, I want my SSH host keys to survive reboot, so that clients don't get host-key-changed warnings.
13. As an operator, I want my Machine Age Key to survive reboot, so that the SOPS Runtime Service decrypts secrets on every boot.
14. As an operator, I want my saved NetworkManager connections to survive reboot, so that my laptop boots with wifi.
15. As an operator, I want `/etc/machine-id` to be stable across reboots, so that journald history and machine identity are preserved.
16. As an operator, I want `/home` to remain persistent (not impermanent), so that user data is not at risk.
17. As an operator, I want `/var`, `/var/log`, `/var/cache` to remain persistent (existing behavior preserved), so that logs and pacman state are kept.
18. As an operator, I want `/tmp` to remain ephemeral (existing behavior preserved), so that tmp semantics are unchanged.
19. As an operator, I want pacman writes to `/usr` to survive reboots without re-snapshot, so that system updates are not lost.
20. As an operator, I want pacman writes to `/etc/<pkg>/` to survive reboots, so that new package configs are not lost.
21. As an operator, I want non-persisted edits to `/etc` to vanish on reboot, so that experimental changes don't quietly accumulate.

### Failure modes and safety

22. As an operator, I want the system to fail closed (drop to emergency shell) if `@blank` is missing on any Rollback Dataset, so that I never silently lose the impermanence guarantee.
23. As an operator, I want the system to fail closed if `/persist` fails to mount, so that the system never boots with empty system-identity files masquerading as "fine."
24. As an operator, I want a clear error message in emergency shell, so that I can diagnose without consulting documentation.
25. As an operator, I want the Blank Snapshot to genuinely be blank (no secrets baked in), so that the snapshot is safe to inspect or share.

### Runtime tooling

26. As an operator, I want a single tool (`os impermanence`) for managing Persist Extensions after install, so that I don't reinvent the procedure each time.
27. As an operator, I want `os impermanence add <path>` to write the path into my host config first, then apply it, so that the host config remains the source of truth.
28. As an operator, I want `add` to copy current data from the live path into `/persist` before binding, so that I don't lose the data I'm trying to preserve.
29. As an operator, I want `add` to detect directory vs file automatically, so that I don't have to flag it explicitly.
30. As an operator, I want `os impermanence remove <path>` to reverse the operation cleanly, so that experiments are reversible.
31. As an operator, I want `os impermanence status` to list active Persist Mounts and show `zfs diff` against `@blank`, so that I can see what's currently persisting and what's drifted.
32. As an operator, I want `os impermanence apply-defaults` to regenerate Curated Persist Defaults from the installer's current list, so that pulling an updated dotfiles repo can pick up new defaults without a re-install.
33. As an operator, I want the tool to refuse to edit Curated Persist Defaults directly, so that I cannot accidentally remove a system-identity persist path.

### Recovery

34. As an operator, I want documented recovery procedures for missing `@blank`, so that a broken system can be repaired from a live USB.
35. As an operator, I want documented recovery for missing or unimportable `/persist`, so that I can diagnose pool-level issues.
36. As an operator, I want a documented procedure to temporarily disable Impermanence for inspection, so that I can debug drift without destroying it.
37. As an operator, I want an honest acknowledgement that permanently disabling Impermanence is best done via re-install, so that I don't try to undo it in-place and corrupt the system.
38. As an operator, I want `os impermanence apply-defaults` to be idempotent, so that I can re-run it to recover from accidental unit-file deletion.

### Integration with existing features

39. As an operator, I want Impermanence to work alongside SOPS, so that the Machine Age Key derived from SSH host keys survives across reboots via the Curated Persist Defaults.
40. As an operator, I want Impermanence to work alongside ZFS native encryption, so that the Rollback Hook runs after pool unlock and before dataset mount.
41. As an operator, I want Impermanence to work in single-disk and multi-disk topologies, so that the same configuration shape works across machine layouts.
42. As an operator, I want the ESP mirror hook to keep working unchanged, so that multi-ESP boots remain mirrored after every pacman transaction.
43. As an operator, I want the paccache hook to keep working unchanged, so that pacman cache cleanup is unaffected.
44. As an operator, I want both systemd-boot and grub bootloader adapters to work with Impermanence, so that bootloader choice is independent of this feature.

### Documentation

45. As an operator, I want a dedicated README chapter for Impermanence, so that the feature is discoverable.
46. As an operator, I want ASCII architecture diagrams in the README, so that I can grok the dataset/mount topology and boot-time flow.
47. As an operator, I want recovery procedures documented in the README, so that I can self-service emergency recovery.
48. As a developer, I want an ADR capturing the impermanence architecture decision, so that the rationale survives in the repo even if the implementation changes.
49. As a developer, I want CONTEXT.md to define every new term (Impermanence, Persist Dataset, Rollback Datasets, Blank Snapshot, Rollback Hook, Bootstrap Mount, Persist Mount, Curated Persist Defaults, Persist Extensions, Pacman Resnapshot Hook, Impermanence Tool), so that future conversations have shared language.

### Developer experience

50. As a developer, I want `lib/chroot/impermanence.sh` to be a self-contained deep module, so that it can be tested in isolation from the rest of the install flow.
51. As a developer, I want the Curated Persist Defaults list defined in one place (a bash array sourced by both the chroot module and the runtime tool), so that the curated list has a single source of truth.
52. As a developer, I want bats unit tests for the chroot module, so that unit-level behavior is verifiable without spinning up a VM.
53. As a developer, I want bats unit tests for the runtime tool's verbs, so that the operator CLI is independently verifiable.
54. As a developer, I want VM integration fixtures covering single-disk, multi-disk, KDE+SOPS, and KDE+encrypted, so that the cross-cutting integration points are exercised.
55. As a developer, I want the validation rules to match the existing `lib/validation.sh` style, so that error messages are consistent.

## Implementation Decisions

### Architectural decisions (recorded in ADR 0008)

- **Persistence mechanism is ZFS dataset rollback to a Blank Snapshot.** Rejected alternatives: tmpfs root (too large a deviation from existing ZFS-on-root); overlayfs root (doesn't fit rolling-release model); rolling back all of `rpool/ROOT/arch` (would erase every pacman update).
- **Finer-grained dataset granularity, not all of `/`.** Rolled back: `rpool/ROOT/etc`, `rpool/ROOT/root`, `rpool/ROOT/opt`, `rpool/ROOT/srv`, `rpool/ROOT/usrlocal`. NOT rolled back: `rpool/ROOT/arch` (so pacman writes to `/usr` survive). `/home`, `/var`, `/var/log`, `/var/cache` remain their own datasets (already separate and persistent).
- **Two-layer config artifact placement.** Bootstrap files (the pair that bind `/persist/etc/systemd/system` and `/persist/etc/tmpfiles.d` into their `/etc` counterparts) live in `/usr/lib/` (on the non-rolled-back `rpool/ROOT/arch`, naturally persistent). Persist Payload (per-path `.mount` units and tmpfiles snippets for extensions) lives on the Persist Dataset, operator-editable at runtime.
- **Curated Persist Defaults are vendor-shipped.** Unit files for the curated essentials live in `/usr/lib/systemd/system/` alongside the bootstrap, regenerated by the installer at install time and by `os impermanence apply-defaults` at runtime. Operators cannot edit them via the runtime tool.
- **Move-not-copy at install time.** Curated paths are moved (not copied) from `/etc` etc. onto the Persist Dataset before `@blank` is taken, so the snapshot contains no secrets.
- **Fail-closed safety.** Rollback Hook fails closed on missing `@blank`; Bootstrap Mount has `RequiredBy=local-fs.target` so a failed `/persist` mount cascades to emergency.

### Schema additions

- **`install.jsonc` — `options.impermanence`** (object form):
  ```jsonc
  "impermanence": {
    "enabled": false,
    "dataset": "rpool/persist",
    "mount":   "/persist"
  }
  ```
  When `enabled` is `false` (default), the rest of the object is ignored. The dataset must live on the same pool as `rpool/ROOT/arch` (validated).
- **Host config / Host Core — `persist`** (object with two arrays):
  ```jsonc
  "persist": {
    "directories": ["/etc/wireguard", "/var/lib/myapp"],
    "files":       ["/etc/foo.conf"]
  }
  ```
  Each entry is an absolute path. Deep-merged across Host Core and the specific Host Config per the standard merge rules. Trailing slashes are not significant (because dirs and files are in separate arrays).

### Validation rules (`lib/validation.sh`)

Errors:
- `Persist path must be absolute: '<path>'.`
- `Persist path must not contain '..' or '~': '<path>'.`
- `Persist file is a directory on disk: '<path>'. Move to persist.directories.`
- `Persist directory is a file on disk: '<path>'. Move to persist.files.`

Warnings:
- `Persist path '<path>' is under <dataset>, already persistent. Redundant.` (paths under `/home`, `/var`, `/var/log`, `/var/cache`, `/tmp`)
- `Persist path '<path>' is in curated defaults. Redundant.`
- `Host '<host>' declares persist paths but impermanence is disabled.`

### Module: `lib/chroot/impermanence.sh` (new — deep)

Single public entry: invoked by `lib/chroot/configure.sh` as the last chroot step. Responsibilities:

1. Read `options.impermanence` from `install-state.json`. Exit 0 if disabled.
2. Create Rollback Datasets: `rpool/ROOT/etc`, `rpool/ROOT/root`, `rpool/ROOT/opt`, `rpool/ROOT/srv`, `rpool/ROOT/usrlocal`. Each with `mountpoint=<path>` and `canmount=on`.
3. Create the Persist Dataset at the configured name and mountpoint.
4. Generate Bootstrap Mount artifacts into `/usr/lib/`:
   - `/usr/lib/tmpfiles.d/impermanence-bootstrap.conf` — creates `/etc/systemd/system/` and `/etc/tmpfiles.d/` placeholders.
   - `/usr/lib/systemd/system/persist-etc-systemd-system.mount`
   - `/usr/lib/systemd/system/persist-etc-tmpfiles-d.mount`
   - Symlinks under `local-fs.target.wants/` to enable both.
5. Generate Curated Persist Defaults' Persist Mount units into `/usr/lib/systemd/system/` and tmpfiles entries into `/usr/lib/tmpfiles.d/impermanence-curated.conf`. Source list from `CURATED_DIRS` and `CURATED_FILES` bash arrays defined at the top of the module.
6. Generate Persist Extension units into `/persist/etc/systemd/system/` and tmpfiles entries into `/persist/etc/tmpfiles.d/impermanence-extensions.conf`. Source from merged `persist.directories` and `persist.files`.
7. Move curated paths' contents from `/etc` etc. onto `/persist/<path>`. Persist Extension paths similarly.
8. Take `@blank` snapshot on every Rollback Dataset.
9. Write the manifest `/usr/lib/impermanence/defaults.manifest` (sorted list of curated paths) for use by the runtime tool's `apply-defaults` verb.

The Curated Defaults list is the bash arrays at the top of the module — single source of truth, sourced by both the chroot module and the runtime tool.

### Module: `tools/impermanence.sh` (new — operator CLI)

Verbs (each a separate function):
- `add <path>` — detects dir vs file; appends to `persist.directories` or `persist.files` in `hosts/<hostname>/config.jsonc` (via `lib/jsonc.sh`); copies live data to `/persist/<path>`; writes a Persist Mount unit to `/persist/etc/systemd/system/persist-<slug>.mount`; writes a tmpfiles entry to `/persist/etc/tmpfiles.d/impermanence-extensions.conf`; `systemctl daemon-reload && systemctl start persist-<slug>.mount`.
- `remove <path>` — reverses `add`: stop+disable the mount, remove unit, remove tmpfiles entry, optionally move data back to live path (with confirmation), remove from host config jsonc.
- `status` — lists `systemctl list-units 'persist-*.mount'`; runs `zfs diff rpool/ROOT/<ds>@blank rpool/ROOT/<ds>` for each Rollback Dataset.
- `apply-defaults` — reads `CURATED_DIRS`/`CURATED_FILES` from `lib/chroot/impermanence.sh`; diffs against `/usr/lib/impermanence/defaults.manifest`; adds units for new entries, removes units for deleted entries; rewrites the manifest; `daemon-reload`.

The tool refuses to operate on Curated Persist Default paths (looked up via the manifest) — `add` and `remove` error out, telling the user the path is a curated default.

### Module: mkinitcpio Rollback Hook (new)

Two files written into the live system by `lib/chroot/impermanence.sh` (templated with the dataset list baked in):
- `/etc/initcpio/install/zfs-rollback` — install-time hook.
- `/etc/initcpio/hooks/zfs-rollback` — runtime hook with one function `run_hook`. For each Rollback Dataset, checks that `@blank` exists, then runs `zfs rollback -r <ds>@blank`. If any `@blank` is missing, the hook drops to emergency shell via `launch_interactive_shell` (or equivalent) with a clear message.

`lib/chroot/initcpio.sh` updated: when impermanence is enabled, insert `zfs-rollback` into `HOOKS=` between `zfs` and `filesystems`.

### Module: Pacman Resnapshot Hook (new)

- `/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook` (PostTransaction, Operation = Install|Upgrade|Remove, Target = `*`)
- Helper script `/usr/lib/impermanence/resnapshot.sh` — for each Rollback Dataset: `zfs destroy rpool/ROOT/<ds>@blank && zfs snapshot rpool/ROOT/<ds>@blank`. Idempotent; logs to journal.

### Module: `lib/zfs-pools.sh` (modified)

New helper `_create_impermanence_datasets <pool_name> <persist_dataset> <persist_mount>`: creates the five Rollback Datasets and the Persist Dataset. Called by `_create_os_datasets` (or alongside it from layout modules) when impermanence is enabled in install state.

### Module: layout modules (modified)

`lib/layout-single.sh` and `lib/layout-multi.sh`: when impermanence is enabled, invoke `_create_impermanence_datasets` after `_create_os_datasets`.

### Module: `lib/config.sh` (modified)

- Parse `options.impermanence` as an object; default to `{enabled: false, dataset: "rpool/persist", mount: "/persist"}` when absent or partial.
- Parse `persist.{directories,files}` from Host Core and Host Config; deep-merge per existing rules.

### Module: `lib/chroot/configure.sh` (modified)

Invoke `impermanence.sh` as the last chroot step, after program installation and after all other configure-phase modules.

### Module: `install.jsonc` (modified)

Add the `options.impermanence` skeleton with `enabled: false` and the default `dataset`/`mount` strings.

### Deferred to v2 (not built now)

- Pre-transaction pacman drift-check hook (strict mode). Documented as a known leak in v1.
- `os impermanence diff`, `accept-drift`, `revert-drift` verbs (depend on strict mode).
- `/home` impermanence. Out of scope.
- Per-directory exclusions in persist declarations. Operators use granular allowlisting instead.
- Persist Dataset on `dpool`. Validated against in v1.

## Testing Decisions

### What makes a good test for this feature

Tests should verify *external behavior*, not internal implementation:
- **Chroot module unit tests** verify the side effects an installer would observe: which datasets were created, which unit files exist with what contents, which paths are present on `/persist` after the module runs, whether `@blank` snapshots exist on the expected datasets. They mock `zfs` and assert on `zfs` command invocations rather than reaching for a real ZFS pool.
- **Runtime tool unit tests** verify each verb's effect on the filesystem: `add /etc/foo` produces the expected unit file, tmpfiles entry, jsonc edit, and data move. They run against a tmpdir fixture, not a live system.
- **VM integration fixtures** verify true end-to-end behavior: the system installs, reboots, and impermanence works — SSH host keys persist, an unpersisted edit vanishes, a pacman install survives a reboot. They exist to catch integration regressions that unit tests cannot (initramfs hook ordering, systemd unit ordering at real boot, ZFS interaction with the real kernel).

### Modules to be tested

- **`lib/chroot/impermanence.sh`** — via `tests/chroot-impermanence.bats`. Verify dataset creation calls, unit file generation, tmpfiles content, move semantics (curated paths absent from source after move, present on `/persist`), snapshot calls. Mock `zfs` via the existing chroot-test mocking pattern.
- **`tools/impermanence.sh`** — via `tests/impermanence-tool.bats`. Verify each verb against a fixture tmpdir: `add` writes correct unit + tmpfiles + jsonc edit + data copy; `remove` reverses; `status` reports active mounts; `apply-defaults` diffs manifest correctly (adds, removes, updates).
- **VM integration** — four fixtures:
  - `tests/vm/testing-single-disk-impermanent.sh` — base case.
  - `tests/vm/testing-multi-os-mirror-impermanent.sh` — multi-disk + mirror.
  - `tests/vm/testing-single-disk-impermanent-kde-sops.sh` — KDE + SOPS (verifies Machine Age Key survives via persisted `/etc/ssh` + `/etc/secrets`, SOPS Runtime Service decrypts on second boot).
  - `tests/vm/testing-single-disk-impermanent-kde-encrypted.sh` — KDE + ZFS native encryption (verifies Rollback Hook ordering vs pool unlock).

### Prior art for tests

- **bats unit pattern**: `tests/chroot-fstab.bats`, `tests/chroot-password.bats`, `tests/chroot-create-user.bats` — same chroot-module testing pattern with mocked external commands.
- **bats command-mocking**: `tests/zfs-pools.bats` — pattern for mocking `zfs` and `zpool` invocations and asserting on argument structure.
- **VM fixture pattern**: `tests/vm/testing-single-disk.sh`, `tests/vm/testing-multi-os-mirror.sh` — established pattern via `tests/vm/_harness.sh`. New fixtures follow same shape, differing only in their `install.jsonc` content and post-install verification commands.
- **Validator tests**: `tests/configs.bats` — pattern for validation rule unit tests.

## Out of Scope

- **`/home` impermanence.** `/home` remains its own ZFS dataset, persistent across reboots. Per-user-home impermanence (the maximalist NixOS pattern) is rejected for v1 due to the prohibitive maintenance cost of the persist list for user apps.
- **Per-directory exclusions** in persist declarations (e.g. "persist `/var/lib/foo` except `/var/lib/foo/cache`"). Operators use granular allowlisting instead. Exclusions deferred until a concrete use case appears.
- **Pre-transaction pacman drift check (strict mode).** Deferred to v2. The v1 ships with a documented leak: user edits to non-persisted paths made before a pacman transaction get baked into the new `@blank` and survive one extra reboot. The fix is opt-in strict mode with `os impermanence diff / accept-drift / revert-drift` verbs; the design exists but is not built now.
- **Persist Dataset on `dpool`** or any pool other than the OS pool. Validated against in v1. The initramfs Rollback Hook runs in the early boot window where only the OS pool is reliably available; supporting a separate data pool for persist requires pushing the bind mounts past early-boot services that need persisted state, which breaks the model.
- **In-place permanent disable** of Impermanence. Re-install is the supported path. Documented in the README recovery section.
- **`os impermanence` as a top-level binary or PATH entry.** v1 ships it as `tools/impermanence.sh`, invoked via the repo's existing tool-running convention (`$DOTFILES/.os/tools/impermanence.sh ...`). A `~/.local/bin/os` wrapper is a follow-up.
- **`.os/vm/` persistent VM fixture for Impermanence.** Manual-testing VM not built in v1; operators copy an existing `vm-*.sh` and toggle the impermanence flag themselves.
- **README chapter content writing.** The PRD specifies the chapter exists and outlines its contents (enable, declare extensions, runtime tool, recovery scenarios 1–5, two ASCII diagrams, v1 limitations); the actual prose is a separate task scoped explicitly by the operator.

## Further Notes

### Relationship to existing features

- **SOPS / Machine Age Key.** The Curated Persist Defaults include both `/etc/ssh/` (whose `ssh_host_ed25519_key` is the derivation source for the Machine Age Key via `ssh-to-age`) and `/etc/secrets/` (where the Machine Age Key itself lives). Either one alone would be enough to recover, but both are persisted for belt-and-suspenders. The SOPS Runtime Service is unaffected by Impermanence — it reads `/etc/secrets/age/keys.txt` like before, which now happens to be a bind mount from `/persist/etc/secrets/age/keys.txt`.
- **ZFS encryption.** When `options.encryption=true`, the existing ZFS initramfs hook prompts for the passphrase and unlocks the pool before any datasets mount. The new Rollback Hook is ordered *after* the `zfs` hook (which handles unlock) and *before* `filesystems` (which mounts), so the rollback runs against an unlocked, importable pool.
- **ESP mirror hook and paccache hook.** Both live in `/etc/pacman.d/hooks/`, which is in the Curated Persist Defaults via the `/etc/pacman.d/` directory entry. They survive rollback for free. Their execed scripts/binaries live under `/usr/bin/` (not rolled back) or are inline in the hook file. No interaction.
- **`zfs-mount-generator`.** The new Rollback Datasets carry standard ZFS `mountpoint` and `canmount` properties, so they're discovered and mounted by `zfs-mount-generator` like every other dataset. No fstab entries needed.

### Mental model

`@blank` for each Rollback Dataset captures "the state pacman last produced." It is *not* "the state at install." Every pacman transaction re-snapshots, so the baseline slides forward over time. This is correct for system files (kept fresh) but creates the documented v1 leak for user edits to non-persisted paths made *before* a pacman run. The leak window equals "time since the operator's last pacman transaction." On a daily-driver workstation, this is typically < 24h.

The promise of v1 is "reset on every boot, except when a pacman transaction has run since your last edit." The promise of v2 (strict mode) will be "reset on every boot, period — and pacman refuses to run with uncommitted drift."

### File creation summary

New files:
- `lib/chroot/impermanence.sh`
- `tools/impermanence.sh`
- `tests/chroot-impermanence.bats`
- `tests/impermanence-tool.bats`
- `tests/vm/testing-single-disk-impermanent.sh`
- `tests/vm/testing-multi-os-mirror-impermanent.sh`
- `tests/vm/testing-single-disk-impermanent-kde-sops.sh`
- `tests/vm/testing-single-disk-impermanent-kde-encrypted.sh`

Modified files:
- `install.jsonc`
- `lib/config.sh`
- `lib/validation.sh`
- `lib/zfs-pools.sh`
- `lib/layout-single.sh`
- `lib/layout-multi.sh`
- `lib/chroot/initcpio.sh`
- `lib/chroot/configure.sh`
- `README.md` (new chapter, separate task)

Already committed (during the grilling session):
- `CONTEXT.md` — 10 new glossary entries.
- `docs/adr/0008-impermanence-via-zfs-dataset-rollback.md` — full ADR.
