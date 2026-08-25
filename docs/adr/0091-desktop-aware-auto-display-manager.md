# `auto` display manager is desktop-aware, not fleet-wide SDDM

---
Status: accepted. Supersedes the `auto` resolution in ADR 0069 (DM is an
operator choice) and the fleet-wide-SDDM rule in ADR 0068/0067's superseding
note. Keeps ADR 0069's operator-override model.
---

`environment.display_manager=auto` resolves **from the resolved desktop set**:

- KDE-free, non-empty set (hyprland and/or niri) → `greetd`.
- Any set containing `kde` → `sddm`.
- Empty set → `none`.

A concrete `greetd`/`sddm` still passes through unchanged, and a concrete DM
with no desktop still aborts at config-load (ADR 0069). The DM stays an
**operator choice** — this changes only what `auto` picks; it is **not** a hard
menu lock (Q2 chose the smart-default path over reversing 0069).

## Context

Two things were out of step. ADR 0069's body states `auto` = "greetd if hyprland
is in the desktop set, else sddm," but the shipped code
(`_resolve_env_display_manager`) resolves `auto` → `sddm` **fleet-wide**, citing
ADR 0068 (seatd made SDDM able to launch Hyprland, so greetd was no longer
*forced*). The two disagree, and niri — a KDE-free wlroots-style session with
the same seatd seat-master model as Hyprland — had no place in either rule.

The operator's mental model is clean and worth encoding as the default: a greeter
that matches the session family. Pure-Wayland tiling sessions (hyprland, niri)
pair with greetd/tuigreet; a Plasma session pairs with SDDM's graphical greeter.
seatd (ADR 0068) means this is a *preference*, not a technical constraint — so it
is a smart default, freely overridable, not a lock.

## Considered options

- **Hard-lock the DM by desktop set** (grey out SDDM when KDE is absent) —
  rejected: reverses ADR 0069's operator-choice for no technical gain (seatd
  lets SDDM drive niri/Hyprland fine) and would need the menu's first real
  cross-field lock.
- **Keep fleet-wide `auto`→SDDM** — rejected: contradicts ADR 0069's own body,
  and gives a KDE-free niri/Hyprland box a graphical greeter the operator did
  not want as the default.
- **Confirm-on-override** — deferred: the advisory default is enough; a
  confirmation gate can be added later if the default surprises anyone.

## Consequences

- `_resolve_env_display_manager` is corrected to the desktop-aware rule above
  and now also recognises niri as a KDE-free (greetd) session.
- Profiles that omit `display_manager` on a KDE-free box now get greetd (was
  SDDM under the shipped code); KDE and KDE+Hyprland/niri co-installs still get
  SDDM. Explicit DMs are unaffected.
- The Package Resolver's `display-manager`-keyed derived set follows the
  resolved DM unchanged (ADR 0069).
- CONTEXT.md's **Display Manager** entry is updated to state the desktop-aware
  `auto` rule and include niri; the code/ADR drift is closed.
