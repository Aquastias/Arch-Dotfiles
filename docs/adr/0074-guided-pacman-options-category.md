# Pacman Options is its own Guided category, applied authoritatively

We surface the pacman `[options]` block flags (`ILoveCandy`, `Color`,
`VerbosePkgLists`, `DisableDownloadTimeout`, `NoProgressBar`,
`ParallelDownloads`) as a dedicated **Pacman** Configuration Category under
`options.pacman.*`, placed right after Mirrors & Repositories since both edit
`pacman.conf`. It is written **authoritatively** to the host `/etc/pacman.conf`
before pacstrap — each managed flag is uncommented when on and commented out
when off, so the file always reflects the toggles regardless of the ISO's
shipped defaults, and the target inherits it via the existing `chroot.sh` copy
(same seam as `enable_optional_repos`).

## Considered options

- **Fold into Mirrors & Repositories** — rejected: that category already owns
  repos/mirrors; mixing in cosmetic/behavioural `[options]` flags muddies it.
  A separate category keeps each screen coherent.
- **Additive apply (only ON toggles act)** — rejected: an OFF toggle then can't
  turn off a flag the ISO shipped on, and the result depends on ISO drift.
  Authoritative apply is idempotent and predictable.

## Consequences

- `CheckSpace` is deliberately **not** exposed: the ZFS path force-disables it
  (`disable_checkspace`), so a toggle would fight the installer. `multilib`
  stays under Optional Repositories (ADR 0072), not duplicated here.
- Authority is scoped to the managed set only — unrelated lines (`SigLevel`,
  includes, custom repos) are never touched.
- `options.pacman.*` becomes committed Host Profile surface: adding/renaming a
  key means updating the closed-schema allowlist + accessors in lockstep.
