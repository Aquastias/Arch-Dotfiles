Status: done

# Package modules → lib/packages/

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Group the package-resolution files into a new `lib/packages/` folder,
update every `source`/path reference, and relocate their tests to the
mirrored `tests/packages/` path. Move only — no behavior change, no
function renames.

Rename mapping:

```
packages.sh     -> packages/list.sh
kernel.sh       -> packages/kernel.sh
iso-resolver.sh -> packages/iso-resolver.sh
```

Base Package List (ADR 0026), Kernel Selection + ZFS Module Guard
(ADR 0024), and archzfs-Compatible ISO (ADR 0023) are preserved — files
move only.

## Acceptance criteria

- [ ] 3 package files moved into `lib/packages/` per the mapping
- [ ] Every `source`/path reference updated repo-wide
- [ ] All public function names unchanged (e.g. `collect_packages`)
- [ ] Tests relocated to mirrored `tests/packages/` paths
- [ ] Full bats suite passes unchanged (no behavior change)

## Blocked by

- None - can start immediately

## Comments

Implemented. `packages.sh`→`lib/packages/list.sh`, `kernel.sh`→
`lib/packages/kernel.sh`, `iso-resolver.sh`→`lib/packages/iso-resolver.sh`.
Refs updated: `03-install.sh`, `audit.sh`, `tools/fetch-iso.sh`.

Cross-folder kernel sources fixed (kernel left `lib/`): `config/
accessors.sh` (`../packages/kernel.sh`) and the `$_LIB_DIR/../kernel.sh`
test/repo fallback in `chroot/bootloader-systemd-boot.sh` +
`chroot/initcpio.sh` (their flat `$_LIB_DIR/kernel.sh` chroot-staged
primary path stays; chroot cp dest stays `/root/lib-chroot/kernel.sh`).
Also fixed both VM harnesses' `${LIB_DIR}/iso-resolver.sh` — a
variable-prefixed source the literal `lib/` rename missed.
`${_STDLIB_DIR}/packages.sh` (= `lib/shell/packages.sh`) left untouched.

3 tests relocated to `tests/packages/`. Verified: bats **917/0**,
`audit.sh` **82/82**, `shellcheck.sh` clean.
