# niri as a core-only DE adapter with an optional Noctalia shell preset

---
Status: accepted. Extends ADR 0005 (adapter pattern), ADR 0021/0062 (core-only
adapters), ADR 0088 (adapter seeds /etc/skel).
---

niri joins as a third selectable `environment.desktop` value
(`_VALID_DESKTOP=(kde hyprland niri)`) via a new `extras/desktop/niri/niri.sh`
adapter. Like Hyprland it is **core-only** (ADR 0021/0062): the compositor plus
session plumbing only. Unlike Hyprland it needs far less — the `niri` package
(`extra` repo) ships its own `/usr/share/wayland-sessions/niri.desktop` +
`niri-session` + `niri-portals.conf` and pulls `seatd` as a hard dep, so there
is no `start-hyprland`-style launcher shim and no aquamarine DRM pin.

Adapter core: `niri` (pulls seatd), `xdg-desktop-portal-gnome` (screencast),
`xdg-desktop-portal-gtk`, `polkit-kde-agent`, `wl-clipboard`; `systemctl enable
seatd` (same seat-master rationale as Hyprland, ADR 0068). No session file is
authored — the packaged `niri.desktop` is correct and appears in the curated
`/usr/local/share/wayland-sessions` dir the DM adapters read.

## The Noctalia shell preset

A niri install alone is a bare scrollable compositor — no bar, launcher,
notifications, or lock. To make **niri+noctalia a prepared work environment**
without violating core-only, the shell layer is an explicit, menu-visible
choice: `environment.niri_shell` (`noctalia` | `none`, default `noctalia`),
meaningful only when niri is in the desktop set. `none` yields bare niri.

Noctalia (v5, `noctalia` in `extra` — the v4 AUR/Quickshell line is
unmaintained) is a single-package shell providing bar, launcher, notifications,
clipboard history, control center, lock, wallpaper, and OSD — nearly the whole
QoL layer in one package. The `noctalia` preset therefore installs:

- **Shell:** `noctalia`.
- **Session-completing set** (the genuine gaps Noctalia does not cover): `kitty`
  (the operator's existing terminal) and `brightnessctl` (Noctalia's brightness
  OSD shells out to it). Screenshot is niri-native; NetworkManager + PipeWire
  are already in the base (ADR 0026 / audio map), so the network/audio/notify
  widgets need nothing extra. `cava` (visualizer, a known audio sample-rate
  footgun) and `cliphist` are off by default.
- **Config glue, seeded into `/etc/skel`** (ADR 0088 precedent, scoped to this
  preset): a **minimal** `/etc/skel/.config/niri/config.kdl` that
  `spawn-at-startup "noctalia --daemon"` and binds kitty + niri's native
  screenshot. Noctalia self-generates its own look on first run — only the glue
  is seeded, never Noctalia's theming. Under `niri_shell=none` **nothing** is
  seeded (Hyprland core-only precedent — dotfiles own the config).
- **Bitwarden plugin** (ADR 0091 covers only DM; plugin detail here): the
  official "Bitwarden Vault Search" Luau plugin, `git` sparse-checked-out at a
  **pinned ref** from `noctalia-dev/official-plugins` into
  `/etc/skel/.config/noctalia/plugins/bitwarden/` and registered in skel's
  `plugins.json`; `bitwarden-cli` (`extra`) installed for the `bw` backend.
  Offline → the plugin is skipped with a warning; the install still succeeds.
  The installer only installs + wires + enables — `bw login` is interactive and
  is the user's first-boot step ("prepared" = ready-to-auth, not pre-authed).

Preset component bools live in `install-niri.jsonc` (`bitwarden`, `cava`,
`cliphist`), mirroring KDE's `install-kde.jsonc` file-level toggles (ADR 0087) —
one honest home for "what the preset pulls in," without adding menu rows per
plugin. The Package Resolver reads the same file so what installs and what it
reports cannot drift (ADR 0021).

## Considered alternatives

- **Bundle Noctalia into the niri adapter core** — rejected: it makes "just
  niri" impossible and re-crosses the core-only line for every niri install.
- **Ship no config (Hyprland precedent, dotfiles own everything)** — rejected
  for the preset: without a seeded `config.kdl` the first login is a bare niri
  with no shell, which is not "prepared for work." Kept for `niri_shell=none`.
- **Vendor the Bitwarden plugin's Luau into this repo** — rejected: carries and
  hand-maintains third-party code; a pinned sparse-checkout is deterministic
  without vendoring, and the chroot already fetches from the network.
- **A menu row per plugin** — rejected: file-level bools in `install-niri.jsonc`
  match KDE and keep the Environment menu to the one `niri_shell` row.
- **Bind Noctalia to niri only vs. any wlroots DE** — niri-bound now; the field
  is written so extending to Hyprland later is a gate change, not a rewrite.

## Consequences

- The Tier-2 install matrix gains niri cells automatically — `desktop` is a
  menu-derived pairwise axis, so widening the enum and regenerating adds them
  (mirror of ADR 0050/0062). The `desktop-verify` harness must prove an
  SDDM/greetd-launched niri session comes up (seatd path, as for Hyprland).
- `environment.niri_shell` is a new Environment menu row (enum, same plumbing as
  `environment.display_manager`); absent ⇒ `noctalia`.
- First niri login under the preset is a working desktop (shell autostarts);
  bare niri (`none`) is unconfigured by design.
- The glossary gains **Wayland Shell Companion** and updates **Desktop
  Environment Adapter** (three adapters now).
