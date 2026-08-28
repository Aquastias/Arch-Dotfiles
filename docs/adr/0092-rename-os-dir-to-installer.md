# Rename `.os/` to `.installer/`

The installer tree lived at `.os/`. The name misread as "an operating
system" when the directory is in fact a scripted **Arch installer** — its
README titles it "Arch Linux Installer". Worse, `.os` collided visually
with the repo's genuine `os_pool` / "OS disk" / "OS topology" domain
terms (the ZFS root pool and the disks it lands on), so "os" meant two
unrelated things. We rename the directory to `.installer/`, which states
what it is.

## Scope

Folder path and its **folder-derived satellites** only:

- `.os/` → `.installer/` (moved with `git mv`, history preserved).
- The `OS_DIR` env var → `INSTALLER_DIR` (its whole reason to exist is
  pointing at this directory). Clean rename, no back-compat alias — a
  personal-dotfiles repo with no external consumers, and an alias would
  reintroduce the "os" ghost being removed.
- The runtime staging dir `/var/tmp/.os-runtime` → `.installer-runtime`.
- Exclude-lists, `.gitignore` globs, the deployed `searxng-update@`
  systemd unit path, `.githooks/pre-push`, and doc/CLAUDE/AGENTS paths.

## Deliberately untouched

- **`os_pool`** and prose "OS disk / OS pool / OS topology" — a real ZFS
  hardware concept (the operating-system root pool), not folder-derived.
- Local test-scoped vars (`OSDIR`, `os_dir`, `OS_FIX`) — self-contained
  temp dirs, not the `INSTALLER_DIR` contract; renaming is churn.
- `.scratch/` historical issue notes — point-in-time records of work
  against `.os/`; rewriting them falsifies the record.

## Consequences

- A behaviourally inert rename: no logic changed, so the bats suite is
  the regression guard.
- **Live systems** running the `searxng-update@` user unit need a
  re-deploy and `systemctl --user daemon-reload` to pick up the new path.
- Historical ADRs keep saying `.os/` verbatim — they are point-in-time
  records. This ADR is the bridge from the old path to the new one.
