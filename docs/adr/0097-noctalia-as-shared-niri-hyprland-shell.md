# Noctalia is the shared niri/Hyprland shell, selected via `wayland_shell`

---
Status: accepted. **Supersedes ADR 0096 whole** (shared keybinds + skel-seeded
Hyprland config) — its keybind-parity vocabulary survives, relocated into the
Noctalia-wired `hyprland.conf`. Extends ADR 0090 (niri adapter + Noctalia
preset), 0093 (enriched plugin set), 0095 (skel-seed delivery). Amends ADR
0062's Hyprland core-only for the *shell* layer only.
---

ADR 0096 gave niri and Hyprland one keybind vocabulary but two different
environments: niri ran the full Noctalia work shell, while Hyprland stayed
core-only with the launcher key bound to `wofi` and the lock key to `hyprlock`.
Switching compositors felt the same at the keyboard but was a different desktop.
The operator wants the **same environment on both** — bar, launcher,
notifications, lock, wallpaper, OSD, palette, plugins — with the **compositor as
the only thing that changes**. Noctalia already runs on any major Wayland
compositor, so the shell becomes compositor-agnostic and both adapters serve it.

## Decision

**Noctalia is the [[Wayland Shell Companion]] for both niri and Hyprland**, one
shared config, only the compositor config differing.

1. **`environment.niri_shell` → `environment.wayland_shell`** (`noctalia` |
   `none`, default `noctalia`), honored by **both** wlroots compositors; KDE
   ignores it. `noctalia` seeds the shared preset + the Noctalia-wired
   compositor config; `none` = **truly bare** for *both* (nothing seeded — the
   operator's dotfiles own it), so bare Hyprland no longer ships curated
   keybinds. The model stays symmetric rather than special-casing Hyprland.

2. **Shared preset extracted to `lib/chroot/noctalia-preset.sh`.** All preset
   logic that lived in `niri.sh` (package set, plugin vendoring, curated-config
   seeding) moves to one module both adapters source, passing the compositor tag,
   which config file(s) to seed, and which plugin slice to vendor. One source,
   no niri↔Hyprland drift.

3. **`config.toml` stays single-source and encodes the plugin split by
   *omission*** (its `[plugins].enabled` carries the **shared-core plugins
   only** — never `niri-*` or `hypr-*`, and the look). The per-compositor slice
   is *vendored* by each adapter into skel, and the existing first-login enable
   one-shot (ADR 0093) enables whatever `[local]` plugins it finds — so `niri-*`
   activate on niri and `hypr-*` on Hyprland off the *same* seeded `config.toml`,
   with neither slice's ids ever written into it. The byte-identical config is
   how the seeded look stays shared while the enabled plugin set still reflects
   the compositor.

4. **Plugin slices.** Shared core plugins are unchanged. The niri slice
   (`niri-active-workspace`, `niri-animations`, `niri-displays`) gets its
   Hyprland counterpart slice (`hypr-*` equivalents), so the *features* match on
   both, each backed by the compositor-native plugin. Each `hypr-*` id is
   verified to exist at the pinned community ref before it ships.

5. **`hyprland.conf` becomes the Noctalia-hosting variant:** `exec-once`
   autostarts `noctalia --daemon` + the enable-plugins one-shot; the launcher and
   lock keys route through Noctalia IPC (`noctalia msg panel-toggle launcher` /
   `noctalia msg session lock`), dropping the `wofi` launcher bind. The ADR 0096
   keybind vocabulary is retained; Hyprland-native extras (scratchpad, mouse
   drag) stay — "only the backend differs."

6. **`hyprlock` leaves core.** Noctalia locks via `ext-session-lock-v1` (PAM,
   blurred backdrop) on Hyprland natively, so the dedicated locker is redundant.
   Under `wayland_shell=none` there is no lock bind at all (bare, like bare niri)
   — no dead key, no safety hole.

7. **`install-niri.jsonc` → shared `install-noctalia.jsonc`**, read by both
   adapters and the [[Package Resolver]]: shared plugin bools + companions
   (`cava`, `cliphist`) + the `laptop` gate + a `niri` slice + a `hyprland`
   slice; each adapter installs shared + its own slice.

## Considered options

- **Special-case Hyprland to always-Noctalia, keep `niri_shell` niri-scoped** —
  rejected: asymmetric, and the field name reads wrong the moment the same shell
  runs on Hyprland. `wayland_shell` with a symmetric `none` is cleaner.
- **Leave the preset logic in `niri.sh` and duplicate it in `hyprland.sh`** —
  rejected: two authored copies of the vendor/seed path guarantee drift (the
  exact failure ADR 0012/0094 set out to kill).
- **Ship only compositor-agnostic plugins on both** — rejected: loses the
  workspace / animation / display widgets; the `hypr-*` slice restores them.
- **Keep `hyprlock` in core as an emergency fallback** — rejected: re-muddies
  core-only for a locker Noctalia replaces; the lock-before-suspend bug (below)
  is accepted as a known-issue instead.

## Consequences

- ADR 0096 is fully superseded; the **bare-Hyprland** combo (core-only +
  curated keybinds) is retired — `wayland_shell=none` is now truly bare for both
  compositors.
- **Known issue:** on some Hyprland versions, locking *then* suspending can crash
  the Noctalia lock (recover via TTY). Accepted, since `hyprlock` is dropped;
  revisit only if it bites in practice.
- The Tier-2 matrix axis renames `niri_shell` → `wayland_shell`;
  `desktop-verify` gains a **Hyprland+Noctalia** bring-up cell (seatd DRM-master
  path, shell autostarts, `ext-session-lock`). No dedicated bare-Hyprland cell —
  that is compositor-package-only and trivial.
- The glossary's **Wayland Shell Companion** entry becomes compositor-agnostic;
  **Desktop Environment Adapter** and the `wayland_shell` field reference update.
