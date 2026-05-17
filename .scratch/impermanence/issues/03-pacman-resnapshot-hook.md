Status: ready-for-agent

# Pacman Resnapshot Hook

## Parent

`.scratch/impermanence/PRD.md`

## What to build

Install a pacman post-transaction hook that re-takes the Blank Snapshot on every Rollback Dataset after each successful pacman transaction. Without this hook, any pacman writes to `/etc/<pkg>/` (and similar paths on the other Rollback Datasets) would be reverted on next reboot, breaking newly-installed packages.

Scope:

- A pacman hook file installed at the standard hook location, named so it runs last (`zz-` prefix). Trigger: `Type=Package`, `Operation=Install|Upgrade|Remove`, `Target=*`. Action: `When=PostTransaction`, invoking a helper script.
- A helper script that, for each Rollback Dataset, destroys the old `@blank` and takes a new one. Operations on the five datasets are sequential and idempotent. Errors are logged to the journal but do not abort the pacman transaction (pacman has already succeeded by the time the hook runs).
- Both files are placed by the installer when impermanence is enabled. Both files live on paths that survive impermanence: the hook file lives under `/etc/pacman.d/hooks/` (covered by Curated Persist Defaults), the helper script lives under `/usr/lib/` (on the non-rolled-back root dataset). No special handling needed for the hook to survive reboots.
- Idempotency: running the helper script when `@blank` doesn't exist yet (e.g. an install where the hook fires before the install completes) creates it fresh without error.
- When `options.impermanence.enabled=false`, neither file is installed. The pacman hook only exists on impermanent systems.

This slice intentionally does NOT close the v1 leak (user edits to non-persisted paths made before a pacman run get baked into the new `@blank`). That fix is the pre-transaction strict-mode hook, deferred to v2 per the PRD.

Document the v1 leak as a comment in the helper script so a future reader understands why no pre-transaction wipe exists.

## Acceptance criteria

- [ ] Pacman hook file is installed only when impermanence is enabled
- [ ] Hook runs `PostTransaction` for `Install|Upgrade|Remove` of `Type=Package`
- [ ] Helper script re-snapshots `@blank` on every Rollback Dataset (`rpool/ROOT/{etc,root,opt,srv,usrlocal}`)
- [ ] Helper script is idempotent — running it when `@blank` is absent creates it; running it when present destroys and replaces it
- [ ] Hook helper script logs to the journal on each invocation
- [ ] After installing a test package (e.g. one that ships a `/etc/<pkg>/` config), reboot, and verify the package's `/etc/<pkg>/` config survives the rollback
- [ ] `tests/chroot-impermanence.bats` covers hook/helper file generation (presence, contents, mocked `zfs` calls)

## Blocked by

- `.scratch/impermanence/issues/01-core-impermanence.md`
