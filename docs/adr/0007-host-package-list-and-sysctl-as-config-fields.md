# ADR 0007: Host package list and sysctl as config fields

**Status:** Accepted

## Context

The `.pkglist/` directory held host-specific package lists (`pkglist-repo.txt`, `pkglist-aur.txt`) and a sysctl helper script (`set_swappiness.sh`) that were maintained separately from the `.os/` installer. These were not consumed by the installer; they were a parallel, manual workflow.

The goals were to:
1. Migrate package lists into the declarative `.os/` config system.
2. Declare sysctl defaults declaratively alongside other host configuration.
3. Remove `.pkglist/`.

## Decision

**Package lists:** Add a `packages` object to host `config.jsonc` files (not Host Core) with two arrays: `repo` (installed via pacstrap) and `aur` (installed via paru for the primary user). The alternative — a program dir per package — would produce hundreds of boilerplate dirs with no install logic.

Both `repo` and `aur` live in the host config (not user config) because the lists are machine-specific. AUR packages need a user context (paru) but are not user-specific — they're installed once per machine for the system, via the first declared user's paru instance.

**Sysctl:** Add a `sysctl` object to Host Core, containing key-value pairs written to `/etc/sysctl.d/99-os.conf` during the profiles phase. Goes in core because the defaults (e.g. `vm.swappiness`) apply to every machine. Hosts can add keys; the standard deep-merge applies.

**Tools:** Move `save-pkglist.sh` and `install-pkglist.sh` to `.os/tools/` as host-agnostic utilities (hostname argument, defaults to `$(hostname)`). The txt package list files are deleted — the configs are now the source of truth.

## Consequences

- Adding a package to a host no longer requires creating a program directory.
- `packages.repo` packages are installed during pacstrap (before chroot); `packages.aur` packages are installed after paru bootstrap (during profiles phase).
- The installer deduplicates `packages.repo` against the hardcoded base package list.
- `save-pkglist.sh` / `install-pkglist.sh` remain available for running on an already-installed system (drift recovery, new machine bootstrap without a fresh install).
