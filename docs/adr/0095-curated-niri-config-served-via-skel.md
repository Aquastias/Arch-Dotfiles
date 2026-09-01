# The curated niri/Noctalia config is served by the installer via /etc/skel

---
Status: accepted. Supersedes ADR 0094's delivery mechanism (stow-at-install);
keeps 0094's single-source-in-the-dotfiles-repo and its config *content*
decisions intact.
---

ADR 0094 moved the curated `config.kdl` / `config.toml` / helper scripts out of
`/etc/skel` into the repo's stow tree and made **the Runner's per-user `stow`**
deliver them at install ("the Runner always does this"). Two problems surfaced
in practice:

1. The Runner only stows when a host sets `dotfiles_repo`, and no committed host
   does — so 0094's "always" never happened: a fresh niri install booted on
   niri's built-in defaults, not the curated look.
2. Making the **installer** clone + stow a user's dotfiles is the wrong seam.
   Stowing is a thing the **operator** does on their installed system; the
   installer should hand them a working default, not take over their `~`.

## Decision

The **niri adapter seeds the curated config into `/etc/skel`** (so a fresh box
boots the full look by default), and the installer **never stows**.

Single source is preserved: the authoritative files stay at the repo root
(`.config/niri/config.kdl`, `.config/noctalia/config.toml`,
`.local/bin/noctalia-*`), still an ordinary stow package the **operator** may
`stow` on their installed system. `lib/chroot.sh` stages those exact files into
the niri adapter's `curated/` dir (the extras tree is all the chroot adapter can
reach), and `extras/desktop/niri/niri.sh` copies them into `/etc/skel` — a copy
of the one source, not a second-authored heredoc, so there is no drift.

`dotfiles_repo` and the Runner's `_profiles_clone_dotfiles` stay in the codebase
as an **opt-in** capability for a host that genuinely wants it, but nothing sets
it by default and the VM harness does not.

## Why this is not the drift 0094 killed

ADR 0094 rejected "keep the skel seed **and** a stowed copy" because that meant
two *authored* sources of the same file. Here `/etc/skel` receives a **copy**
of the single repo source at install time (`install -Dm644` from
`.config/…`), the same way plugin folders are already vendored into skel. Edit
the repo file, re-install (or re-stow) — one place to change.

## Consequences

- niri + Noctalia now boot the curated config on a fresh install with no operator
  action, and `stow .` from the repo still works for the operator's own machine.
- The `install-niri.jsonc` bools, `packages/niri.sh`, and the curated
  `config.toml` `enabled` list must still be kept in step by hand (unchanged from
  0094).
- Plugin **vendoring** into skel is unchanged (network sparse-checkout at the
  pinned ref); only the config files gained a skel seed beside them.
- The glossary's **Wayland Shell Companion** entry is updated: curated config is
  skel-seeded from a single repo source (not stow-delivered by the installer).
