Status: ready-for-agent

# Disk Config accessors + remove stale `.desktop.kde` reference

## Parent

`.scratch/config-modules-refactor/PRD.md`

## What to build

Issue 02 migrated software-config defaults into `install-config.sh`,
but disk-layout fields (a separate cluster per ADR 0001) still carry
inline default-fallbacks in five modules. Add accessors for the
remaining schema fields and migrate the consumers:

New `install_config_*` accessors:

- `install_config_os_pool_name` (default `rpool`)
- `install_config_storage_pool_name` (default `dpool`)
- `install_config_storage_mount` (default `/data`)
- `install_config_ashift` (default `12`)
- `install_config_os_pool_ashift` (default `13`)
- `install_config_storage_group_ashift <index>` (default `12`)
- `install_config_encryption_enabled` (default `false`)

Consumer sites to migrate (multi-line `cfgo` + `${X:-default}`):

- `lib/layout-single.sh:231-241` — os_pool_name, storage_pool_name,
  ashift, storage_mount
- `lib/layout-multi.sh:336-337,400-401` — os_pool.ashift,
  storage_groups[*].ashift
- `lib/config.sh:272-279` (summary) — pool names, storage_mount
- `lib/config.sh:370-371`, `lib/zfs-pools.sh:92,133` —
  options.encryption

## Stale reference cleanup

`lib/config.sh:355-357` reads `.desktop.kde`, which no longer exists
in the schema (replaced by `environment.desktop` per ADR 0005). The
summary block is dead code reading a phantom field. Remove the three
lines (`kde="$(cfgo '.desktop.kde')"`, the fallback, and the
`printf … "kde:"` line at config.sh:366).

## Acceptance criteria

- [ ] All accessors above implemented with bats coverage in
      `tests/install-config.bats`
- [ ] `grep -rnB1 '^\s*[a-z_]\+="\${[a-z_]\+:-' .os/lib/ | grep -B0 -A1 cfgo`
      returns no hits after migration
- [ ] `.desktop.kde` reference removed from `lib/config.sh`
- [ ] Existing bats suite passes
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- `.scratch/config-modules-refactor/issues/02-migrate-install-config-consumers.md`
