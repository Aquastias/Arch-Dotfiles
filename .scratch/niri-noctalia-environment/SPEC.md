# Spec: niri desktop environment with an optional Noctalia work shell

Status: ready-for-agent

Related: ADR 0090 (this feature — niri adapter + Noctalia preset), ADR 0091
(this feature — desktop-aware `auto` display manager). Builds on ADR 0005
(adapter pattern), ADR 0021/0062 (core-only adapters), ADR 0069 (DM is an
operator choice), ADR 0087/0088 (KDE `install-*.jsonc` toggles + `/etc/skel`
seeding), ADR 0068 (seatd), ADR 0061 (impermanence DM alias), ADR 0046
(combination matrix).

## Problem Statement

As the operator, I can only pick KDE or Hyprland for my desktop. I want niri —
a scrollable-tiling Wayland compositor — as a first-class choice. More than the
bare compositor, I want a niri box that is ready to work the moment it boots:
a shell with a bar, launcher, notifications, clipboard history, lock, wallpaper,
and a Bitwarden vault at my fingertips — without hand-assembling it from a dozen
packages and dotfiles after every reinstall. I also still want the escape hatch
of installing niri completely bare when I intend to bring my own config.

Separately, the display-manager default surprises me: on a KDE-free Wayland box
the installer's `auto` gives me SDDM's graphical greeter when I would expect the
lightweight tuigreet that suits a tiling session — and niri has no place in the
current `auto` rule at all.

## Solution

As the operator, I get `niri` as a third `environment.desktop` value, installed
by its own core-only Desktop Environment Adapter exactly like KDE and Hyprland.

On top of niri I get a menu-visible choice, `environment.niri_shell`, defaulting
to `noctalia`: the **Noctalia work preset**. Selecting it gives me a prepared
desktop on first login — Noctalia (one package covering bar, launcher,
notifications, clipboard history, control center, lock, wallpaper, OSD), the two
gaps Noctalia does not cover (my existing kitty terminal + brightnessctl for its
brightness OSD), a minimal seeded niri config that autostarts the shell, and the
official Bitwarden plugin wired up and ready for me to `bw login`. Flipping
`niri_shell` to `none` gives me bare niri that seeds nothing — my dotfiles own
it, exactly as Hyprland works today.

The display-manager `auto` default becomes desktop-aware: greetd/tuigreet for a
KDE-free Wayland set (Hyprland and/or niri), SDDM when KDE is present, none when
there is no desktop. It stays a smart default I can always override — never a
hard menu lock — because seatd makes any greeter launch any session.

## User Stories

1. As the operator, I want `niri` as a selectable desktop, so that I can run a
   scrollable-tiling compositor from the installer.
2. As the operator, I want niri selectable alongside KDE and/or Hyprland, so
   that I can co-install compositors and switch at login.
3. As the operator, I want the niri adapter to install only the session core,
   so that a niri choice does not drag in opinionated apps I did not ask for.
4. As the operator, I want niri's seat manager (seatd) enabled automatically, so
   that the compositor obtains DRM master and starts on real hardware.
5. As the operator, I want the packaged niri session to appear in the greeter,
   so that I can log into niri without authoring a session file.
6. As the operator, I want screencasting to work under niri, so that I can share
   my screen in meetings (the GNOME portal is installed).
7. As the operator, I want a menu choice `niri_shell` defaulting to `noctalia`,
   so that a fresh niri box is a working desktop, not an empty scrollable void.
8. As the operator, I want `niri_shell=none` to give me bare niri that seeds no
   config, so that my own dotfiles fully own the setup.
9. As the operator, I want the Noctalia preset to install the `noctalia`
   package, so that I get the whole shell layer from one package.
10. As the operator, I want kitty and brightnessctl installed with the preset,
    so that the two things Noctalia cannot provide (a terminal, brightness
    control for its OSD) are present.
11. As the operator, I want a minimal `config.kdl` seeded into `/etc/skel` that
    autostarts Noctalia and binds kitty plus niri's native screenshot, so that
    my first login is immediately usable.
12. As the operator, I do NOT want the installer to seed Noctalia's theming or
    look, so that its first-run defaults and my dotfiles stay in control of
    appearance.
13. As the operator, I want the Bitwarden plugin installed and registered under
    the preset, so that a vault search is available in the launcher after I log
    in.
14. As the operator, I want `bitwarden-cli` installed with the plugin, so that
    the `bw` backend the plugin needs is present.
15. As the operator, I understand the installer cannot log me into Bitwarden, so
    that I know `bw login` is my own first-boot step ("prepared" = ready-to-auth).
16. As the operator, I want the Bitwarden plugin fetched at a pinned ref, so
    that the install is deterministic and does not carry third-party code in my
    repo.
17. As the operator installing offline, I want the plugin fetch to skip with a
    warning rather than fail, so that the install still completes.
18. As the operator, I want to drop preset components (Bitwarden, cava,
    cliphist) via bools in `install-niri.jsonc`, so that I can trim the preset
    without a menu row per plugin.
19. As the operator, I want cava and cliphist off by default, so that I avoid
    Noctalia's known audio sample-rate footgun and unneeded backends.
20. As the operator using the Guided Installer, I want niri in the desktop
    multi-select, so that I can pick it from the menu.
21. As the operator using the Guided Installer, I want a `niri_shell` row in the
    Environment category, so that I can choose the shell preset from the menu.
22. As the operator, I want the `niri_shell` row shown with correct Display
    Labels (Noctalia / none), so that the option reads cleanly.
23. As the operator, I want an override dot on `niri_shell` when I change it, so
    that I can see what I have touched.
24. As the operator, I want `auto` display manager to give me greetd on a
    KDE-free box (Hyprland and/or niri) and SDDM when KDE is present, so that the
    greeter matches my session family without my having to set it.
25. As the operator, I want `auto` to give no display manager on a headless
    host, so that a server is not handed a greeter it cannot use.
26. As the operator, I want to override the display manager to SDDM on a niri box
    if I prefer it, so that the smart default never becomes a lock.
27. As the operator, I want an explicit greetd or SDDM choice honored verbatim
    for a niri desktop, so that my selection wins over the auto derivation.
28. As the operator, I want an unknown `niri_shell` value to abort at config load
    with its path, so that a typo fails fast rather than mid-install.
29. As the operator authoring a Host Profile by hand, I want to set
    `environment.niri_shell`, so that the shell choice is captured in the
    machine's committed audit artifact.
30. As the operator inspecting packages, I want niri's core and the Noctalia
    preset reported as their own derived sets, so that I can see what a niri
    config installs and why.
31. As the operator running impermanence on a niri box, I want my greeter to
    survive the rolled-back root, so that I get a login screen on every boot.
32. As the maintainer, I want adding niri to be a new adapter directory plus a
    field, so that no Environment Runner dispatch code changes.
33. As the maintainer, I want the niri desktop enum widening to auto-add niri
    cells to the combination matrix, so that coverage tracks the menu with no
    hand-editing.
34. As the maintainer, I want `environment.niri_shell` registered as a matrix
    axis, so that the registry-covers-menu guard does not hard-fail the
    generator.
35. As the maintainer, I want the desktop-aware `auto` rule to live in exactly
    one shared place (or be asserted identical in both), so that the resolver
    and the installer cannot drift on what `auto` means.
36. As the maintainer running the VM matrix, I want a niri session proven to
    come up under the resolved display manager, so that the new adapter has
    automated coverage.

## Implementation Decisions

**niri joins the desktop enum.** `niri` is added to the valid desktop set
alongside `kde` and `hyprland`. `environment.desktop` stays array-shaped
(multi-select); KDE + Hyprland + niri and any subset are valid. The Layer
Resolver treats it like the other desktop values — no new merge classification.

**niri Desktop Environment Adapter (new module).** A new adapter under the
`extras/desktop/<name>/` contract, dispatched by convention from the Environment
Runner with no runner change. It is **core-only** (ADR 0021/0062): it installs
the compositor and session plumbing only — the `niri` package (which pulls
`seatd`), both XDG portals (GNOME for screencast, GTK), the polkit agent, and
the Wayland clipboard bridge — and enables `seatd` (same DRM-master rationale as
Hyprland, ADR 0068). It authors **no** session file and **no** aquamarine DRM
pin: the `niri` package ships its own session and niri handles GPU selection
itself. The packaged niri session is picked up by the curated wayland-sessions
directory the Display Manager Adapters already read.

**New Environment field `environment.niri_shell`.** Added to the closed Host
Profile schema as an optional string discriminator, values `noctalia` (default)
| `none`. Meaningful only when `niri` is in the resolved desktop set. Modeled on
`environment.display_manager` (same enum + Display Label + replace-key
machinery). Resolved and exported to the chroot the same way `ENVIRONMENT_DESKTOP`
is, so the niri adapter reads it as an environment variable — no Install State
field is added (nothing post-chroot needs it).

**The Noctalia preset lives in the niri adapter, gated on `niri_shell`.** When
`niri_shell=noctalia`, the adapter additionally:
- installs `noctalia`, `kitty`, `brightnessctl`, and `bitwarden-cli` via pacman
  (all in `extra`; Noctalia v5 — the v4 AUR/Quickshell line is unmaintained);
- seeds a **minimal** `/etc/skel/.config/niri/config.kdl` that
  `spawn-at-startup "noctalia --daemon"` and binds kitty + niri's native
  screenshot — **glue only, never Noctalia's theming** (Noctalia self-generates
  its look on first run);
- installs the official "Bitwarden Vault Search" Luau plugin by `git`
  sparse-checkout of the `bitwarden/` subfolder from `noctalia-dev/official-plugins`
  at a **pinned ref**, into `/etc/skel/.config/noctalia/plugins/bitwarden/`, and
  registers it in skel's `plugins.json`. Offline (or fetch failure) → the plugin
  is skipped with a warning and the install continues.

When `niri_shell=none` the adapter installs the core only and seeds nothing
(Hyprland core-only precedent).

**Preset component toggles in `install-niri.jsonc` (new file).** Mirrors KDE's
`install-kde.jsonc` (ADR 0087): file-level bools the adapter and the Package
Resolver both read, so what installs and what the resolver reports cannot drift.
Contents: `bitwarden: true`, `cava: false`, `cliphist: false`. These are not
menu rows — the single menu control is the `niri_shell` on/off choice.

**Desktop-aware `auto` display manager (ADR 0091).** Environment resolution's
display-manager step changes `auto` to resolve from the desktop set: `greetd`
for a KDE-free non-empty set (hyprland and/or niri), `sddm` when the set contains
`kde`, `none` when empty. Concrete `greetd`/`sddm` still pass through. This
supersedes the shipped fleet-wide-`auto`→`sddm` code and aligns with (and closes
a drift against) ADR 0069's stated intent, extending it to niri. It is a default,
not a lock — the menu still offers all three DM values.

**Package Resolver.** niri's core is reported as its own derived set (mirroring
`kde-shell`), and the Noctalia preset packages are a further derived set keyed on
`niri_shell` + `install-niri.jsonc`, so `explain-packages` and the guided derived
section show exactly what a niri config installs and why. The resolver's existing
display-manager `auto` re-derivation is updated to the desktop-aware rule so it
matches the installer (the two-place lockstep called out under Testing).

**Guided Installer menu.** `niri` is added to the `environment.desktop` enum
options, and a new `environment.niri_shell` Environment row (enum `noctalia` /
`none`, default `noctalia`, Display Labels Noctalia / none) is added, reusing the
single-source enum + Display Label machinery. The Environment category summary is
extended to name the niri shell.

**Combination matrix registry.** `environment.niri_shell` is registered as a
pairwise-affecting axis (weight heavy — its variation pulls the Noctalia package
set and an AUR-shaped git fetch), satisfying the registry-covers-menu assertion.
Widening the `desktop` enum auto-adds niri cells (`desktop` is already a
pairwise-affecting axis).

## Testing Decisions

A good test here asserts external behavior at a module's public seam — the
resolved value, the abort, the packages/services a run installs/enables, the
files a run writes — never internal helper wiring. All seams below already exist;
the only new artifact is one adapter test file, a clone of the existing Hyprland
adapter test harness.

- **Config-load resolution (primary seam)** — extend `environment-resolution.bats`:
  `niri` resolves as a valid desktop; `niri_shell` defaults to `noctalia` and
  passes explicit values through; desktop-aware `auto` resolves to
  greetd/sddm/none across KDE-free, KDE-present, and empty desktop sets including
  niri. Prior art: the GPU and display-manager `auto` cases in the same file.
- **Config-load validation** — extend `environment-validation.bats`: an unknown
  `niri_shell` value aborts with its path; niri is accepted in the desktop set.
  Prior art: the existing desktop/display-manager validation cases.
- **niri Desktop Environment Adapter** — new `tests/extras/niri-adapter.bats`,
  running the adapter as a subprocess with pacman/systemctl/git stubbed on PATH
  and `ROOT`/skel/session dirs redirected to a tmpdir. Assert: core packages +
  `seatd` enable always; under `niri_shell=noctalia` the preset packages, the
  seeded `config.kdl` glue (spawns Noctalia, binds kitty), the Bitwarden plugin
  files + `plugins.json` registration, `install-niri.jsonc` bools honored
  (bitwarden off ⇒ not seeded), and the offline path skips the plugin without
  failing; under `niri_shell=none` nothing beyond core is installed or seeded.
  Prior art: `tests/extras/hyprland-adapter.bats` and `kde-adapter.bats`.
- **Package Resolver** — extend `tests/packages/resolver.bats`: the niri-core and
  Noctalia-preset derived sets report the right packages per `niri_shell` and
  `install-niri.jsonc`; the display-manager derived set follows the desktop-aware
  `auto` rule. Prior art: the existing kde-shell and display-manager derived-set
  cases.
- **Guided menu** — extend the menu-enum / guided menu bats: niri appears in the
  desktop options; the `niri_shell` row appears in Environment with its two
  options and correct Display Labels. Prior art: the existing desktop/gpu/
  display-manager row and enum cases.
- **Matrix registry** — the existing `matrix_registry_assert` test proves the
  registry covers `_MENU_FIELDS` exactly; adding the `environment.niri_shell`
  entry keeps it green. Prior art: the registry coverage test.
- **VM integration** — extend the `desktop-verify` harness with a niri cell: the
  SDDM-driven prober (a test launcher, not the product) autologs into the niri
  session and asserts a `===NIRI-SESSION-OK===` marker, plus the resolved
  display manager's service is enabled. Prior art: the `===HYPR-SESSION-OK===`
  env matrix cell and harness.
- **Auto-rule lockstep** — because the desktop-aware `auto` rule lives in both
  `environment.sh` and the resolver, the resolution bats and the resolver bats
  each assert it for the same desktop sets, so a change to one that misses the
  other is caught.

## Out of Scope

- Offering the Noctalia preset for Hyprland (or any non-niri compositor). The
  field is written to generalise later, but `niri_shell` is niri-bound now.
- Seeding Noctalia's own theming, bar layout, or look — only the niri
  `config.kdl` autostart/keybind glue is seeded; appearance is first-run +
  dotfiles.
- Authenticating Bitwarden (`bw login`), configuring a self-hosted server, or
  storing any vault secret — all are the user's post-boot steps.
- Vendoring the Bitwarden plugin's Luau into the repo (a pinned sparse-checkout
  is used instead).
- cava and cliphist as default-on components (present as `install-niri.jsonc`
  bools, off by default).
- A hard menu lock that forbids SDDM on a KDE-free box — the DM stays an
  overridable smart default (ADR 0091 chose this over a lock).
- Any change to the KDE or Hyprland adapters, the Display Manager Adapters, or
  the aquamarine DRM pin, beyond the shared `auto` rule update.
- Additional Noctalia plugins beyond Bitwarden.

## Further Notes

- Noctalia v5 is `pacman -S noctalia` from `extra`; the v4 AUR
  `noctalia-shell`/Quickshell packages are unmaintained and are not used. The v5
  launch command is `noctalia` (`noctalia --daemon` for the compositor autostart
  path); the niri autostart line is `spawn-at-startup "noctalia --daemon"`.
- The Bitwarden plugin requires the official `bitwarden-cli` (`bw`) — it does
  not work with `rbw`. `bitwarden-cli` is in `extra`, so it installs host-side
  via pacman with the rest of the preset.
- niri ships `niri.desktop` + `niri-session` + `niri-portals.conf` and depends on
  `seatd`, which is why the adapter authors no session file and no DRM pin — the
  two hardware fixes the Hyprland adapter needs (start-hyprland shim, aquamarine
  pin) have no niri equivalent.
- NetworkManager and PipeWire are already in the base install, so Noctalia's
  network and audio widgets need no extra packages.
- The desktop-aware `auto` change alters the default greeter on existing
  KDE-free profiles that omit `display_manager` (greetd instead of the shipped
  code's SDDM); this matches ADR 0069's documented intent and is the deliberate
  correction of the code/ADR drift (ADR 0091).
