# ADR 0088: KDE adapter seeds DE config defaults (theme + first-run)

## Status
Accepted. Extends ADR 0021 (adapter owns DE packages) from packages to
config.

## Context
The KDE adapter (`extras/desktop/kde/kde.sh`) installed packages only — it
seeded no configuration. The operator wanted a fresh KDE login to be ready:
**Breeze Dark** by default (with **Papirus-Dark** icons and **Breeze**
cursors), GTK apps following the same dark look, the login screen (SDDM)
matching, and the common apps **not behaving as if first-launched**.

None of that is a package — it is per-user config that normally lives in
`~/.config`. Three homes were available: the user's stow payload (this
repo's `.config/`, where the GTK/kitty config already lives), a runtime
apply (`plasma-apply-lookandfeel`), or system skeleton files. The adapter
runs in the chroot **before** users are created by the Runner, and has no
running Plasma/D-Bus, so a runtime apply is impossible there.

## Decision
The KDE adapter seeds DE defaults into the **system skeleton** it can write
at chroot time — a system default, not one user's personal config:
- `/etc/skel/.config/` for state a user should own and may later change
  (theme selection, per-app first-run state), copied into each home at
  user creation.
- `/etc/xdg/` for read-only fallbacks where a system default is preferable.

Seeded content:
- **Theme**: Breeze Dark global look-and-feel, `Papirus-Dark` icon theme,
  `Breeze` cursors. GTK follows via `breeze-gtk`/`kde-gtk-config`; the
  Catppuccin GTK theming is removed from the stow payload (re-addable
  later).
- **First-run suppression** (ADR Q4-B scope): global welcome noise off
  (Plasma Welcome Center, tip-of-the-day, "what's new" popups) plus curated
  per-app first-run state for the heavy-hitters (Dolphin, Konsole, Kate,
  Okular, Spectacle, Gwenview, Ark). Baloo file indexing left **on**.
- **SDDM**: pinned to the Breeze theme in dark so login → session is
  visually seamless.

## Considered alternatives
- **User stow payload only.** Rejected as the *default* home: it is
  personal to one account and would not make an arbitrary fresh install
  ready. (Personal deep-customization may still layer via stow on top of
  the skel baseline.)
- **Runtime `plasma-apply-lookandfeel`.** Impossible in the chroot (no
  running Plasma/D-Bus); would require a first-boot service.

## Plugin/backend packages
The chosen apps' optional-dependency enhancers (`dolphin-plugins`,
`kio-admin`, `kdegraphics-thumbnailers`, `ffmpegthumbs`, `kimageformats`,
`qt6-imageformats`, `krita-plugin-gmic`, `7zip`, `unrar`, `ebook-tools`,
`opencv`, `darktable`, `noise-suppression-for-voice`, `recordmydesktop`,
`sshfs`, …) live in a new adapter **`plugins`** section of
`install-kde.jsonc`, keyed by app, parsed and toggled exactly like
`apps_list`/`apps_extra`. This extends the adapter's ownership from "the
DE's apps" to "those apps' optdepends" — bending ADR 0021's literal
"DE-implied" test for the generic backends (`opencv`, `darktable`, …),
justified because they exist *only* to enhance adapter-installed apps and
should be deselectable alongside them.

Language-server packages for Kate are the deliberate exception: they are
general dev tooling, not DE-tied, so they live in **Host Core**
`packages.repo` / `packages.aur` (AUR accepted for servers with no `extra`
package), landing on the operator's real machines while VM fixtures exclude
them via `packages.inherit: false`. The adapter's repo-only guarantee is
untouched.

## Consequences
- The adapter now owns DE **config defaults** and its apps' **optdepends**,
  not just the apps — every KDE install boots into the configured dark look
  with quiet, capability-complete apps.
- `/etc/skel` is populated before user creation, so the Runner's
  later-created users inherit it with no ordering hazard.
- Config is baked into home (writable), so the operator can still change
  the theme afterward; `/etc/xdg` fallbacks do not fight per-user edits.
