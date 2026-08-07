# Spec: Operator-selectable Display Manager

Status: ready-for-agent

Related: ADR 0069 (this feature), supersedes ADR 0067; builds on ADR 0068
(seatd), ADR 0061 (impermanence DM alias), ADR 0005 (adapter pattern).

## Problem Statement

As the operator, the installer forces my login screen based purely on which
desktop I pick: greetd + tuigreet is hard-wired whenever Hyprland is present —
both a sole-Hyprland install and a KDE + Hyprland co-install — and SDDM only
ever runs on a KDE-only box. I cannot choose SDDM for a Hyprland or
KDE + Hyprland machine.

That hard-link was a workaround. Hyprland black-screened under SDDM because its
aquamarine backend could not obtain DRM master, and greetd happened to launch
the compositor a way that worked. The real cause was later found to be the seat
manager, not the display manager: enabling seatd gives aquamarine DRM master
directly (ADR 0068), independent of whichever greeter launched the session. So
the reason SDDM was banned for Hyprland is gone, and the forced greetd is now
an arbitrary constraint I want lifted.

## Solution

As the operator, I get a new Environment choice, `display_manager`, that lets me
pick my greeter independently of my desktop. Any display manager can launch any
desktop (full symmetry): SDDM for Hyprland or KDE + Hyprland, greetd for KDE.
The default preserves today's behavior exactly, so every existing profile is
untouched.

The display-manager decision moves out of the desktop adapters into its own
adapter, selected by the new field and run after the desktops are set up, so
the desktops only contribute their sessions and seat manager while the display
manager owns its own package, config, and service.

## User Stories

1. As the operator, I want to select SDDM for a sole-Hyprland install, so that
   I get a graphical greeter instead of tuigreet's TUI.
2. As the operator, I want to select SDDM for a KDE + Hyprland co-install, so
   that both desktops share one graphical greeter.
3. As the operator, I want to select greetd for a KDE-only install, so that I
   get a lightweight TUI greeter if I prefer it.
4. As the operator, I want a default that reproduces today's behavior, so that
   my existing profiles install identically without edits.
5. As the operator, I want `auto` to mean "greetd if Hyprland is selected, else
   SDDM", so that the smart default still applies when I do not care.
6. As the operator, I want `auto` on a server (no desktop) to select no display
   manager, so that a headless host is not given a greeter it cannot use.
7. As the operator, I want an explicit greetd or SDDM choice to be honored
   verbatim, so that my selection is never overridden by the auto derivation.
8. As the operator using the Guided Installer, I want a Display Manager row in
   the Environment category, so that I can pick the greeter from the menu.
9. As the operator, I want the Display Manager menu row to read Auto / greetd /
   SDDM with correct casing, so that the options are legible.
10. As the operator, I want the Environment category summary to mention the
    display manager, so that I know the choice lives there.
11. As the operator, I want a display-manager override to show the standard
    override dot when I change it, so that I can see what I have touched.
12. As the operator authoring a Host Profile by hand, I want to set
    `environment.display_manager`, so that the machine's greeter is captured in
    its committed audit artifact.
13. As the operator, I want an unknown display-manager value to abort at config
    load with its path, so that a typo fails fast rather than mid-install.
14. As the operator, I want a concrete display manager with no desktop selected
    to abort with an actionable message, so that I am not left with a greeter
    that has no session to launch.
15. As the operator picking SDDM for Hyprland, I want SDDM installed even when
    KDE is absent, so that my chosen greeter is actually present.
16. As the operator, I want SDDM and greetd to show the same curated session
    list, so that I never see the packaged crashy Hyprland session in the
    picker regardless of greeter.
17. As the operator on a KDE + Hyprland box, I want both Plasma and Hyprland
    selectable from whichever greeter I chose, so that I can still switch
    desktops at login.
18. As the operator running impermanence, I want my chosen display manager to
    survive the rolled-back root, so that I get a real login screen on every
    boot no matter which greeter I picked.
19. As the operator inspecting packages, I want the display-manager packages
    reported as their own derived set, so that I can see which greeter a config
    installs and why.
20. As the maintainer, I want adding a future display manager to be a new
    adapter directory only, so that no runner or dispatch code changes.
21. As the maintainer, I want the desktop adapters to stop enabling any display
    manager, so that the "who enables what when both desktops are present"
    coordination disappears.
22. As the maintainer, I want the display-manager choice threaded into
    install-state, so that the chroot dispatch sees a concrete greeter name.
23. As the maintainer running the VM matrix, I want the session prober to keep
    working for any chosen display manager, so that a greetd profile still
    verifies sessions and asserts the right greeter is enabled.
24. As the operator, I want SDDM-launched Hyprland to be exercised in the VM,
    so that the newly unlocked path has automated coverage before I trust it on
    real hardware.

## Implementation Decisions

**New Environment Config field.** `environment.display_manager` is added to the
closed Host Profile schema as an optional string discriminator, values `auto`
(default) | `greetd` | `sddm`. It sits beside `environment.desktop` and
`environment.gpu`. The Layer Resolver treats it as a replace key like the other
`environment.*` scalars — no new merge classification.

**`auto` resolution at config load.** Environment resolution gains a
display-manager step modeled on the existing GPU `auto` resolution: `auto`
resolves to `greetd` when `hyprland` is in the resolved desktop set, otherwise
`sddm`, and to `none` when the desktop set is empty. The resolved concrete value
is exported for the chroot dispatch and threaded into Install State as a new
scalar field, modeled on the existing resolved GPU field. A concrete
`greetd`/`sddm` value is passed through unchanged (menu/profile choice wins).

**Validation at config load.** An unknown `display_manager` value aborts with
its schema path (existing closed-schema behavior). A concrete display manager
with an empty desktop set aborts with an actionable message. `auto` with an
empty desktop set is valid and resolves to `none`.

**Display Manager Adapter (new module family).** A new adapter contract,
`extras/dm/<name>/<name>.sh`, with `dm-greetd` and `dm-sddm` as the two
adapters. Each adapter owns exactly its display manager: package install, config
generation, and service enablement. `dm-greetd` installs greetd + tuigreet and
writes the greeter config pointing tuigreet at the curated wayland-sessions
directory. `dm-sddm` installs and enables SDDM and writes an sddm.conf.d drop-in
pinning `Wayland.SessionDir` (and the X `SessionDir`) to the curated
wayland-sessions directory ahead of the packaged one, so both greeters present
the same deduped session list.

**Environment Runner dispatch.** The Environment Runner, after iterating the
resolved desktop array and invoking each Desktop Environment Adapter, invokes
the single Display Manager Adapter matching the resolved `display_manager`
(`extras/dm/<dm>/<dm>.sh`) — by directory convention, no greeter name
hardcoded. Dispatch is skipped when the resolved value is `none`. Running after
the desktop loop guarantees every session file and the seat manager already
exist.

**Desktop adapters relinquish the display manager.** The KDE adapter no longer
installs or enables SDDM. The Hyprland adapter no longer installs greetd/tuigreet
nor writes the greeter config; it keeps writing the curated session files and
enabling seatd. `sddm-kcm` remains a KDE application, not a display-manager
concern.

**Package Resolver.** `sddm` moves out of the KDE-shell derived set into a new
display-manager derived set keyed on the resolved `display_manager`; `greetd`
and `greetd-tuigreet` are added to it. `sddm-kcm` stays in the KDE set.

**Guided Installer menu.** A new Environment menu field `display manager` with
enum options `auto`, `greetd`, `sddm`, default `auto`, and Display Labels Auto /
greetd / SDDM. The Environment category summary is extended to name the display
manager. Reuses the existing single-source enum + Display Label machinery so the
interactive and replay front-ends cannot drift.

**Install State.** One new scalar field carrying the resolved concrete display
manager into the chroot, added to the schema list that keeps the host-side write
and chroot-side load in sync.

**Impermanence.** No change. The enablement relocation already follows the
DM-agnostic `display-manager.service` alias, so any enabled greeter survives the
rolled-back root.

## Testing Decisions

Good tests here assert external behavior at the module's public seam — the
resolved value, the abort, the dispatched adapter, the packages/services a run
would install/enable — never internal helper wiring. All seams below already
exist except the two adapter test files, which are line-for-line clones of the
existing Desktop Environment Adapter tests.

- **Config-load resolution** — extend the environment-resolution bats: `auto`
  resolves to `greetd`/`sddm`/`none` per desktop set; explicit values pass
  through; the concrete value threads into Install State. Prior art: the GPU
  `auto` resolution cases in the same file.
- **Config-load validation** — extend the environment-validation bats: unknown
  value aborts with its path; concrete DM + empty desktop aborts; `auto` +
  empty desktop is accepted. Prior art: existing environment validation cases.
- **Environment Runner dispatch** — extend the environment-runner bats with a
  stub `dm/<name>` adapter: the correct adapter is invoked, after the desktop
  adapters, and skipped when resolved `none`. Prior art: the existing
  desktop-adapter dispatch assertions in that file.
- **Display Manager Adapters** — new `dm-greetd` and `dm-sddm` bats, running
  each adapter as a subprocess with pacman/systemctl stubbed on PATH and config
  writes redirected to a temp dir; assert package install, service enable, and
  the config/`SessionDir` drop-in contents. Prior art: the KDE and Hyprland
  adapter bats.
- **Guided menu** — extend the guided-menu and menu-enum bats: the Display
  Manager row appears in Environment with the three options and correct Display
  Labels. Prior art: existing desktop/gpu row and enum cases.
- **Package Resolver** — extend the resolver bats: the display-manager derived
  set reports the right greeter package for each resolved value; `sddm` no
  longer appears in the KDE-shell set. Prior art: existing derived-set cases.
- **VM integration** — the session prober keeps launching sessions via SDDM
  autologin (a test launcher, not the product) and additionally asserts the
  resolved display manager's service is enabled; SDDM-launched Hyprland is
  already covered (`===HYPR-SESSION-OK===`). Prior art: the existing
  desktop-verify harness and env matrix cells.

## Out of Scope

- A `none` / tty-only display-manager choice as an authored value (only the
  no-desktop derivation yields `none`).
- A greetd-based VM autologin prober; the harness stays SDDM-driven and asserts
  the resolved greeter is enabled instead (per grilling Q2).
- A hardware HITL gate before merge; SDDM-launched Hyprland on real amd is
  verified on the next real install and a failure re-opens ADR 0069 (per Q1).
- Any change to seatd enablement, the curated session-file authoring, or the
  aquamarine DRM pin — all owned by the Hyprland adapter and unchanged.
- Relocating `sddm-kcm` out of the KDE set.
- Display managers beyond greetd and SDDM (the adapter pattern makes a third an
  additive directory later).

## Further Notes

- SDDM-launched Hyprland is proven in the VM on a software GPU (the harness
  autologs into `hyprland.desktop` via SDDM and the compositor comes up); the
  logind-DRM-master failure that motivated ADR 0067 was real-hardware-specific
  and is addressed by seatd (ADR 0068), which the Hyprland adapter enables
  unconditionally regardless of the chosen greeter.
- Because `auto` reproduces the ADR 0067 derivation, no committed profile needs
  editing; the field is purely additive.
