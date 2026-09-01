# Spec: Noctalia as the shared niri/Hyprland shell

Status: ready-for-agent

Related: ADR 0097 (this feature — Noctalia is the shared shell, `wayland_shell`).
Supersedes ADR 0096 (shared keybinds + skel Hyprland config) whole — the keybind
vocabulary survives, relocated into the Noctalia-wired `hyprland.conf`. Builds on
ADR 0090 (niri adapter + Noctalia preset), 0093 (enriched plugin set), 0094/0095
(curated config single-source + skel-seed delivery), 0021/0062 (core-only
adapters — the shell-layer stance this amends). Cursor default is a **separate**
feature (ADR 0098, `.scratch/bibata-cursor-default/`).

## Problem Statement

The operator runs two Wayland compositors — niri and Hyprland — and switches
between them, wanting the switch to change *only the backend*. Today it does not:
niri boots the full Noctalia work shell (bar, launcher, notifications, lock,
wallpaper, OSD, curated plugins, palette), while Hyprland is core-only — its
launcher key spawns `wofi`, its lock key `hyprlock`, and file-manager / media
binds are operator-supplied no-ops. ADR 0096 gave the two the same *keys* but not
the same *desktop*. Switching to Hyprland means losing the entire prepared
environment.

## Solution

Make Noctalia the one shared shell on both compositors. The same `config.toml`
(palette, plugins, bar, dock, lock, OSD) drives both; the **only** per-backend
file is the compositor config (`config.kdl` vs `hyprland.conf`), which already
share a keybind vocabulary. Selecting Hyprland with the shell on gives the
identical environment niri does — bar, launcher, notifications, lock, wallpaper,
OSD — with Hyprland underneath instead of niri. The shell selector generalises
from niri-only to compositor-agnostic; bare (`none`) stays available and
symmetric for both.

## User Stories

1. As an operator who switches between niri and Hyprland, I want the same
   Noctalia bar on both, so that my status/tray/workspace surface never changes.
2. As an operator, I want the same Noctalia launcher (`Super+D`) on both, so that
   finding an app is the identical gesture regardless of compositor.
3. As an operator, I want Noctalia notifications on both, so that alerts look and
   behave the same everywhere.
4. As an operator, I want the Noctalia lockscreen (`Super+Alt+L`) on Hyprland
   too, so that locking is the same PAM-authenticated surface as on niri.
5. As an operator, I want the Noctalia wallpaper, dock, and OSD on Hyprland, so
   that the whole prepared look carries over.
6. As an operator, I want my Rosé Pine palette and the palette-cycle affordance
   to work on Hyprland, so that theming is shared, not re-done per compositor.
7. As an operator, I want the same curated plugin features (updates, audio
   switcher, screen toolkit, etc.) on both, so that my tooling is identical.
8. As an operator, I want the compositor-specific workspace / animation / display
   widgets to work on Hyprland via its native `hypr-*` plugins, so that those
   features exist on both even though the backend differs.
9. As an operator, I want a single shell selector that reads sensibly for both
   compositors (`wayland_shell`, not `niri_shell`), so that the field name is not
   misleading on a Hyprland box.
10. As an operator, I want `wayland_shell=noctalia` to be the default, so that a
    fresh niri or Hyprland box boots the prepared desktop with no extra choice.
11. As an operator, I want `wayland_shell=none` to give a truly bare compositor on
    both (nothing seeded, my dotfiles own it), so that opting out is symmetric and
    predictable.
12. As an operator, I want KDE to ignore `wayland_shell`, so that the field only
    affects the wlroots compositors it is meaningful for.
13. As an operator on a fresh Hyprland box, I want Noctalia to autostart at
    login, so that the shell is up without me wiring `exec-once` by hand.
14. As an operator on a fresh Hyprland box, I want the curated plugins enabled on
    first login, so that the plugin set is live without a manual enable step.
15. As an operator, I want the shared launcher/lock keys on Hyprland to drive
    Noctalia's IPC (not wofi/hyprlock), so that identical keys do identical things.
16. As an operator, I want Hyprland-native extras (scratchpad, mouse-drag
    move/resize) to stay, so that "only the backend differs" still lets each
    compositor keep its own idioms.
17. As an operator, I want `hyprlock` gone from the Hyprland install, so that the
    box is not carrying a redundant locker Noctalia replaces.
18. As an operator, I want the terminal, brightness, and media hardware keys to
    work out-of-box on Hyprland+Noctalia (kitty, brightnessctl, playerctl), so
    that the prepared desktop is complete on Hyprland as it is on niri.
19. As a maintainer, I want one authored source for the Noctalia preset logic
    shared by both adapters, so that niri and Hyprland can never drift.
20. As a maintainer, I want one authored `config.toml`, so that the shared shell
    look has a single owner across both compositors.
21. As a maintainer, I want the per-compositor plugin slices declared in one
    shared toggle file, so that "what the preset pulls in" has one honest home.
22. As a maintainer, I want the Package Resolver to read the same toggle file the
    adapters install from, so that install and query cannot drift.
23. As a maintainer, I want the install matrix to cover Hyprland+Noctalia, so that
    a regression in the shared-shell bring-up is caught.
24. As a maintainer, I want the bare-Hyprland combo retired cleanly, so that
    there is no half-configured Hyprland state to reason about.
25. As an operator, I want a fresh Hyprland+Noctalia box to bring up a working
    session (seatd DRM master, shell autostart, working lock), so that the
    install is usable without post-boot fixing.

## Implementation Decisions

- **Shell selector generalised.** `environment.niri_shell` becomes
  `environment.wayland_shell` (`noctalia` | `none`, default `noctalia`), honored
  by **both** niri and Hyprland when present in the desktop set; KDE ignores it.
  The rename ripples through the environment config loader (validation +
  resolution), the schema accessors, the Guided menu row + its enum, the Guided
  seed default, the Host Profile schema key list, the install matrix registry
  axis, and the VM seed generator. `none` = truly bare for both — nothing seeded,
  operator's dotfiles own it — which retires the ADR 0096 bare-Hyprland
  (core-only + curated keybinds) state.
- **Shared preset module.** The Noctalia preset logic currently inside the niri
  adapter (base package set, plugin dep install, plugin vendoring at the pinned
  ref, curated-config seeding into `/etc/skel`, laptop gating, first-login
  enable one-shot) is extracted into a single shared module that both the niri
  and Hyprland adapters source. Compositor-specific inputs are passed in: the
  compositor tag, which curated config file(s) to seed, and which plugin slice to
  vendor. The module keeps the existing injectable seams (`*_SEED_ROOT`,
  `*_CURATED_DIR`, JSON override, battery glob) so the adapter tests still drive
  it.
- **Hyprland adapter under `wayland_shell=noctalia`.** Installs the shared
  Noctalia preset (shell + kitty + brightnessctl + playerctl + enabled companions
  + enabled-plugin deps), seeds a Noctalia-wired `hyprland.conf` + the shared
  `config.toml` + the Noctalia helper scripts into `/etc/skel`, and vendors the
  Hyprland plugin slice. Retains the existing Hyprland core plumbing (seatd,
  both portals, polkit agent, wl-clipboard, blueman tray, the start-hyprland DRM
  session launcher, the aquamarine hybrid-GPU pin, curated sessions). Under
  `wayland_shell=none` the adapter seeds nothing (bare).
- **`hyprlock` dropped from Hyprland core.** Noctalia locks natively via
  `ext-session-lock-v1`; the dedicated locker is redundant. Under `none` there is
  no lock bind at all (bare), so no dead key.
- **Noctalia-wired `hyprland.conf`.** Autostarts `noctalia --daemon` and the
  first-login enable one-shot via `exec-once`; the shared launcher and lock keys
  route through Noctalia IPC (panel-toggle launcher / session lock), dropping the
  `wofi` launcher bind. The ADR 0096 keybind vocabulary is otherwise retained,
  including the Hyprland-native extras (scratchpad, mouse drag) that niri has no
  equivalent for.
- **Same Noctalia config seeded on both compositors.** The curated
  `config.toml` and the `noctalia-*` helper scripts are the *same single repo
  source* niri already seeds; `chroot.sh` must stage that payload into the
  Hyprland curated dir too (today it stages only `hyprland.conf` for Hyprland),
  so a Hyprland+Noctalia box seeds a `config.toml` byte-identical to the niri
  one. Only the compositor config (`hyprland.conf` vs `config.kdl`) differs. The
  one Noctalia difference between the two boxes is the vendored plugin **slice**
  (`niri-*` vs `hypr-*`), which lives *outside* `config.toml` (see plugin slices
  and the single-source point below) — so the seeded config stays identical while
  the *enabled plugin set still reflects the compositor*.
- **`config.toml` stays single-source, and encodes the plugin split by
  *omission*.** Its `[plugins].enabled` list carries the **shared-core plugins
  only** — never `niri-*` or `hypr-*`. The compositor slice is instead *vendored*
  by each adapter into skel, and the existing first-login one-shot enables
  whatever `[local]` plugins it finds — so `niri-*` activate on a niri box and
  `hypr-*` on a Hyprland box off the *same* `config.toml`, with neither slice's
  ids ever appearing in it. This is the deliberate mechanism by which the seeded
  config "takes into account" the split without becoming per-compositor. The
  drift guard is extended accordingly: the vendored set must equal the config's
  shared-core enabled list **plus** the active slice declared in
  `install-noctalia.jsonc` (not the raw config list).
- **Per-compositor plugin slices.** Shared core plugins are unchanged. The niri
  slice (`niri-active-workspace`, `niri-animations`, `niri-displays`) gains a
  Hyprland counterpart slice of `hypr-*` equivalents. Each `hypr-*` id is
  verified to exist at the pinned community ref before it ships; any that do not
  exist are dropped from the slice.
- **Shared toggle file.** `install-niri.jsonc` becomes the shared
  `install-noctalia.jsonc`, read by both adapters and the Package Resolver:
  shared plugin bools + companions (`cava`, `cliphist`) + the `laptop` gate + a
  `niri` slice + a `hyprland` slice. Each adapter installs shared + its own slice.
- **Shared package map.** The pure Noctalia preset package functions (currently
  in the niri package map) are the shared source both adapters and the Resolver
  read; they gain the Hyprland plugin slice and its deps. niri's compositor-core
  package set stays niri-specific; Hyprland's compositor-core stays in the
  Hyprland adapter.
- **Matrix.** The pairwise axis renames `niri_shell` → `wayland_shell`;
  `desktop-verify` gains a Hyprland+Noctalia bring-up cell (seatd path, shell
  autostart, `ext-session-lock`). No dedicated bare-Hyprland cell — that is
  compositor-package-only and trivial.

## Testing Decisions

- **What a good test asserts:** externally observable adapter behaviour — which
  packages are installed, which files land in `/etc/skel`, that a seeded file is
  a verbatim copy of the single repo source, which plugin folders are vendored —
  never the internal shape of the shared module's functions. Prior art: the
  existing `niri-adapter.bats` / `hyprland-adapter.bats` suites, which stub
  `pacman`/`systemctl`/`git` and inject `ROOT` / `*_SEED_ROOT` / `*_CURATED_DIR`
  temp dirs.
- **`hyprland-adapter.bats` (primary seam).** Under `wayland_shell=noctalia`:
  the Noctalia preset packages are installed; the Noctalia-wired `hyprland.conf`,
  shared `config.toml`, and helper scripts are seeded to `/etc/skel` and equal
  the injected curated source; the Hyprland plugin slice is vendored; `hyprlock`
  is **not** installed; the enable-plugins one-shot is seeded. Under
  `wayland_shell=none`: nothing is seeded and the Noctalia set is not installed.
  The warn-but-do-not-abort behaviour when the curated dir is absent holds.
- **`niri-adapter.bats` (existing seam, reused).** Continues to assert the
  Noctalia preset install + curated niri config seeding, now via the shared
  module; the niri plugin slice is vendored; the `wayland_shell` gate replaces
  the `niri_shell` gate.
- **`packages/resolver.bats`.** The Resolver reports the Noctalia preset set for
  both compositors keyed on `wayland_shell`, reading the shared
  `install-noctalia.jsonc`.
- **`config/environment-validation.bats` + `environment-resolution.bats`.**
  `wayland_shell` accepts `noctalia`/`none`, defaults to `noctalia`, is honored
  for both niri and Hyprland, and rejects unknown values.
- **`config/menu-enum.bats`.** The `wayland_shell` row exposes the enum.
- **`config/noctalia-stow.bats`.** The drift guard equates the config's enabled
  list to the shared core + the active slice.
- **`matrix/matrix-registry.bats`.** The axis is renamed to `wayland_shell`.
- **Not covered by bats:** live compositor bring-up and the correctness of the
  bind lines themselves — the VM `desktop-verify` Hyprland+Noctalia cell covers
  session start; `niri validate` / the running Hyprland compositor validate the
  configs.

## Out of Scope

- The **Bibata Modern Ice cursor default** — its own feature (ADR 0098,
  `.scratch/bibata-cursor-default/`), though it lands in the same adapters.
- Re-introducing curated keybinds for bare Hyprland — the bare (`none`) path is
  deliberately unconfigured, symmetric with bare niri.
- Fixing the upstream Hyprland lock-before-suspend crash — accepted as a
  documented known-issue (recover via TTY) now that `hyprlock` is dropped.
- KDE — unaffected by `wayland_shell`.
- Theming beyond the palette/look already carried in `config.toml`.

## Further Notes

- niri-`*` vs `hypr-*` parity is per-plugin; the slice is only as complete as the
  `hypr-*` ids that actually exist at the pinned community ref. Verify each at
  implementation time and drop any missing rather than blocking the feature.
- The `config.toml` single-source invariant is preserved; the operative source of
  what enables at login remains the vendored `[local]` folders (ADR 0093), with
  `config.toml`'s enabled list the declarative mirror.
- The lock-before-suspend crash was observed on Hyprland 0.53.1 / Noctalia 4.1.1
  in the wild; behaviour on the shipped versions should be spot-checked in the VM
  cell but is not a release blocker.
