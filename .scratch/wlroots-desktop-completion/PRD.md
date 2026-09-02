# Complete the niri+Noctalia and Hyprland+Noctalia daily-driver experience

Status: ready-for-agent

Grounds in ADR 0100 (Noctalia natively owns lock, idle, and polkit; wlroots
desktop completion), amending ADR 0097. Uses the [[Wayland Shell Companion]] /
[[Desktop Environment Adapter]] / [[Package Resolver]] vocabulary.

## Problem Statement

An operator who picks the Noctalia [[Wayland Shell Companion]] on niri or
Hyprland gets a rich shell (bar, launcher, notifications, clipboard, plugins,
Rosé Pine) sitting on a compositor that is only half-configured for daily use:

- Nothing happens on inactivity — the screen never auto-locks, never blanks,
  the laptop never auto-suspends. Locking is a manual keypress only.
- GUI apps that ask for root (mounting a disk, a firewall tool) silently fail:
  the packaged `polkit-kde-agent` is installed but never autostarted.
- On niri the compositor config carries no touchpad / keyboard tuning, so a
  fresh laptop login has no tap-to-click and other defaults feel raw.
- On Hyprland `Super+E` is a dead key — it launches `dolphin`, which the
  adapter deliberately never installs, so there is no working file manager and
  niri has no file-manager key at all.

The operator wants **both** presets to be a finished daily driver — not a themed
compositor under a nice bar.

## Solution

Lean on what Noctalia v5 already provides and fill the genuine gaps, keeping the
two presets symmetric ("one shared shell; only the compositor differs").

- **Lock + idle become active**, configured entirely in the stowed
  `config.toml` using Noctalia's built-in `ext-session-lock-v1` locker and
  built-in idle daemon — zero new packages, identical on both compositors. On
  inactivity the screen dims, then locks, then blanks; the machine locks before
  sleeping; a laptop on battery eventually suspends; a desktop never
  auto-suspends. Idle is inhibited while fullscreen video or audio plays.
- **Privilege prompts work** via a single polkit agent, decided once and
  hardcoded (never two agents racing). Noctalia's own agent is preferred; if it
  proves unavailable, the machine reuses `polkit-kde-agent` when KDE is
  co-installed, otherwise `hyprpolkitagent`.
- **niri feels tuned** — the curated `config.kdl` gains touchpad/keyboard input
  settings, a minimal layout, and window rules.
- **A file manager works on both** — `pcmanfm-qt` ships in the preset with a
  right-click / F4 "open the current folder in kitty" flow, and `Super+E` is
  bound to it on both compositors. It inherits Rosé Pine automatically from
  Noctalia's Qt template.

## User Stories

1. As a Noctalia operator on niri, I want the screen to lock itself after a few
   minutes idle, so that I do not leave an unlocked session when I step away.
2. As a Noctalia operator on Hyprland, I want the same idle-lock behavior, so
   that switching compositors changes nothing about how my desktop protects me.
3. As a laptop operator, I want the monitors to blank after a longer idle, so
   that I save power without the machine fully suspending mid-task.
4. As a laptop operator on battery, I want the machine to suspend after a long
   idle, so that a closed-desk laptop does not drain its battery.
5. As a desktop operator, I want auto-suspend to never fire, so that long
   downloads, builds, or media playback are never cut off by a sleep.
6. As any operator, I want the session to lock before it suspends, so that
   resuming from sleep always lands on the lock screen.
7. As any operator watching a fullscreen video or listening to audio, I want
   idle actions inhibited, so the screen never locks or blanks mid-playback.
8. As any operator, I want a manual lock keybind to keep working exactly as it
   does today, so that I can lock on demand regardless of the idle timers.
9. As any operator, I want a GUI app that needs root (mount a disk, open a
   firewall tool) to show a password prompt, so that privileged actions succeed
   instead of silently failing.
10. As an operator running only wlroots compositors (niri and/or Hyprland with
    no KDE), I want the polkit prompt provided without pulling KDE, so that my
    box stays free of a desktop I do not use.
11. As an operator running KDE alongside niri/Hyprland, I want the wlroots
    sessions to reuse the polkit agent KDE already installs, so that I am not
    carrying a second redundant agent.
12. As any operator, I want exactly one polkit agent active per session, so that
    I never get double password prompts or a race between agents.
13. As a niri laptop operator, I want tap-to-click and natural scrolling out of
    the box, so that the touchpad behaves like every other modern laptop.
14. As a niri operator, I want my keyboard layout and repeat configured, so that
    typing feels right from first login.
15. As a niri operator, I want sensible window rules and a minimal layout, so
    that dialogs and tiling behave without hand-editing the config.
16. As a niri operator moving between machines, I want no display-specific
    output settings baked into the shared config, so that the config stays
    portable across different monitors.
17. As any operator, I want `Super+E` to open a working file manager, so that
    the advertised keybind is not a dead key on a fresh install.
18. As a niri operator, I want the same `Super+E` file-manager key Hyprland has,
    so that the two compositors stay in muscle-memory parity.
19. As any operator, I want the file manager to open the current folder in kitty
    from a right-click and from F4, so that I can drop into a terminal where I
    am browsing.
20. As any operator, I want the file manager to match my Rosé Pine theme without
    extra setup, so that it looks like part of the same desktop.
21. As any operator, I want a lean, useful right-click action set (open in
    kitty, copy path, edit as root, duplicate), so that the common actions are
    one click away without dragging in heavy tooling.
22. As an operator on a minimal or laptop install, I want no Samba or ISO-mount
    tooling pulled in just for a file-manager menu, so that my install stays
    lean.
23. As a maintainer, I want the resolver's reported package set to match what
    the adapters actually install, so that `explain-packages` never drifts from
    reality after this change.
24. As a maintainer, I want the VM desktop-verify harness to prove the polkit
    agent registers and the idle daemon runs in both wlroots cells, so that the
    "Noctalia owns lock/idle/polkit" claim is verified, not assumed.
25. As a maintainer, I want the choice between Noctalia's own polkit agent and
    the fallback ladder resolved once and recorded, so that the installer picks
    packages deterministically at install time rather than guessing per box.
26. As an operator who selects `wayland_shell=none`, I want none of this seeded,
    so that a bare compositor stays truly bare (the ADR 0097 symmetry).
27. As a KDE-only operator, I want the KDE adapter's own polkit agent untouched,
    so that this change never regresses a KDE session.

## Implementation Decisions

Grounded in ADR 0100. No file paths or code below — modules named by role.

### Lock + idle (config-only)
- Enable Noctalia's built-in locker and idle daemon in the curated,
  stow-owned/skel-seeded `config.toml` (the [[Wayland Shell Companion]]'s single
  source). No new packages; byte-identical across compositors per ADR 0097.
- **Idle policy** (the curated default): dim / lock-hint ~2.5 min → lock ~5 min
  → DPMS-off ~10 min; `lock_before_suspend` on; idle inhibited on fullscreen
  video / audio.
- **Auto-suspend is laptop-on-battery only**, gated by the existing `laptop`
  detection already used for the battery plugins in `install-noctalia.jsonc`.
  Desktops get lock + DPMS but no suspend leg.

### Polkit (verify once, hardcode)
- The installer cannot runtime-test Noctalia's agent per box, so this is a
  one-time design decision made during implementation, not a per-install branch.
  Exactly one agent runs per session.
- Verify Noctalia's built-in polkit agent at implementation time (see Testing).
  - **If it works** → the unconditional `polkit-kde-agent` install is removed
    from both wlroots [[Desktop Environment Adapter]]s (niri and Hyprland); no
    agent package is added; the KDE adapter keeps its own `polkit-kde-agent`.
  - **If it fails** → ship the KDE-aware fallback ladder, keyed on the resolved
    `environment.desktop` set (install-time knowledge): KDE co-installed → the
    wlroots sessions reuse the already-present `polkit-kde-agent`; no KDE →
    install `hyprpolkitagent` (official `extra` repo) and autostart it.
- The autostart, when an agent is needed, lives in the shared preset module so
  niri and Hyprland stay in step (no per-adapter drift).

### File manager
- Add `pcmanfm-qt` to the shared preset (declared in `install-noctalia.jsonc`,
  reported by the [[Package Resolver]]).
- Seed a `pcmanfm-qt` settings payload (Preset C layout: compact view,
  tree+Places sidebar, double-click) with `Terminal=kitty` so F4 / right-click
  "Open Terminal" drops into kitty at the current folder.
- Seed a trimmed custom-action set (Open in kitty here, Copy path, Edit as root,
  Duplicate). **Explicitly excluded**: mount-ISO / Samba-share / hash actions,
  so no `samba` / `fuseiso` is dragged into every install.
- Bind `Super+E` to `pcmanfm-qt` on Hyprland (fixing the dead `dolphin` bind)
  and add the same bind to the niri `config.kdl` for parity.
- No extra theming work — pcmanfm-qt is Qt/libfm-qt and inherits the Noctalia
  Qt template's Rosé Pine color scheme automatically.

### niri compositor tuning
- The curated `config.kdl` gains an `input` block (touchpad tap-to-click +
  natural-scroll, keyboard layout/repeat), a minimal `layout` block, and
  `window-rules`.
- **`output` is deliberately omitted** — display scale/mode is host-specific and
  would violate the curated config's portability rule (host-bound surfaces stay
  out, per ADR 0094). Hyprland already carries its `input`/`monitor`/look
  blocks; no change there beyond the `Super+E` fix.

### Symmetry / bare mode
- `wayland_shell=none` seeds nothing new — the bare-compositor symmetry of ADR
  0097 is preserved.

### Hyprland escape hatch (documented, not built)
- If the ADR-0097 lock-then-suspend crash reproduces on Hyprland, that
  compositor alone may flip to `hyprlock` + `hypridle` (Hyprland's canonical
  pair) as a config swap. Not implemented in this spec.

## Testing Decisions

Good tests here assert **external behavior at the highest existing seam** — what
packages land, what seeds to `/etc/skel`, what the resolver reports, and whether
a session actually comes up with a working agent — never internal wiring.

### Seam 1 — Adapter + Resolver bats (existing, primary)
- Extend `niri-adapter.bats` and `hyprland-adapter.bats` (they already drive
  each adapter via `NIRI_SEED_ROOT` / `ENVIRONMENT_WAYLAND_SHELL` / `NIRI_JSON`
  / `NIRI_CURATED_DIR` against a fake pacman). New assertions:
  - On the verify-pass path, `polkit-kde-agent` is **not** installed by either
    wlroots adapter (today's `niri-adapter.bats` asserts it *is* — that
    assertion flips).
  - `pcmanfm-qt` **is** installed under `wayland_shell=noctalia`, and stays out
    under `wayland_shell=none`.
  - The curated `config.toml` / `config.kdl` and the pcmanfm-qt settings +
    custom-action payload are seeded to `/etc/skel` (mirrors the existing
    "seeds the curated config + helpers" tests).
  - The KDE adapter test is unchanged / still green (its `polkit-kde-agent`
    stays).
- Extend `resolver.bats` so the [[Package Resolver]] reports the new set
  (`pcmanfm-qt` in, `polkit-kde-agent` out for wlroots) — the existing
  install-vs-report no-drift contract.
- Prior art: the seed-file and package-set assertions already in
  `niri-adapter.bats`; the drift assertions in `resolver.bats` /
  `explain-packages.bats`.

### Seam 2 — desktop-verify VM cell (existing, lightly extended)
- Extend the `desktop-verify` prober (VM harness fixture) so, in the
  niri+Noctalia and Hyprland+Noctalia cells, beyond the current wayland-socket +
  compositor-process check it also asserts: (a) a polkit authentication agent is
  **registered** on the session bus, and (b) Noctalia's **idle daemon is
  active**. A pass on the "agent registered" check with Noctalia's own agent is
  what resolves the ADR-0100 polkit gate to the verify-pass branch.
- Prior art: the existing per-session OK/FAIL serial-console probe pattern in
  the desktop-verify fixture; the Hyprland+Noctalia bring-up cell (ADR 0097).
- The config *content* correctness (idle timers actually fire, niri accepts the
  new blocks) is proven here; an optional `niri validate` lint may fold into
  Seam 1 only if niri's binary is available in CI.

## Out of Scope

- Reintroducing `hyprlock` / `hypridle` as the default (Noctalia is native now);
  only pre-documented as the Hyprland escape hatch.
- Any `output` / display-scale configuration in the niri config (host-specific).
- The heavy pcmanfm-qt actions (mount ISO, Samba share, hash) and their tooling.
- KDE session behavior — the KDE adapter's polkit agent and theming are
  untouched.
- Fixing the upstream Noctalia idle bugs (suspend-vs-lock race, keep-awake vs
  DPMS) — accepted-and-revisit per ADR 0100.
- Building the Hyprland `hyprlock`+`hypridle` fallback (documented only).

## Further Notes

- The whole feature is symmetric by design: the only per-compositor divergence
  is the niri `config.kdl` tuning (Hyprland already has its equivalents) and the
  `Super+E` fix on both.
- The polkit verification is the single gating unknown; everything else is
  deterministic. Resolve it first (Seam 2 / a manual one-time check) because it
  selects whether any agent package is added at all.
- Known-bug exposure is accepted with the documented Hyprland escape hatch — see
  ADR 0100 Consequences.
