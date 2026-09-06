# Close window binds to Meta+X across KDE, niri and Hyprland

---
Status: accepted. **Amends ADR 0096** (shared niri↔Hyprland keybind vocabulary):
the close-window key moves from `Mod+Q` to `Mod+X`, and the same bind is set on
KDE, so all three environments close the focused window with Meta+X. The KDE
bind rides in the captured `kglobalshortcutsrc` seeded by ADR 0111.
---

ADR 0096 gave niri and Hyprland one shared keybind vocabulary; both closed the
focused window with `Mod+Q`. KDE's default close is `Alt+F4`. The operator wants
**one** close key across every environment — `Meta+X` — so the reflex is the
same whether the session is Plasma, niri or Hyprland.

## Decision

**Close window = `Meta`/`Super`+`X` on all three environments.**

- **niri** — `~/.config/niri/conf.d/keybinds.kdl`: `Mod+X { close-window; }`
  replaces `Mod+Q`.
- **Hyprland** — `~/.config/hypr/conf.d/keybinds.lua`: `SUPER + X` →
  `hl.dsp.window.close()` replaces `SUPER + Q`.
- **KDE** — `kglobalshortcutsrc` `[kwin] Window Close` carries `Meta+X`
  alongside KDE's own `Alt+F4` (`Alt+F4\tMeta+X,Alt+F4,Close Window`), seeded
  via the captured file (ADR 0111).

`Mod+Q` is **freed** on the compositors (not repurposed) — the shared vocabulary
stays minimal (ADR 0096). KDE keeps `Alt+F4` too; the operator asked to *add*
Meta+X there, and it was already set on the reference box.

## Considered options

- **Keep `Mod+Q` and add `Mod+X`** on the compositors — rejected: two close keys
  muddy the shared vocabulary; the operator wants one.
- **Repurpose freed `Mod+Q`** (e.g. to quit-session) — rejected: quit already
  has `Mod+Shift+E` / `Ctrl+Alt+Delete` (ADR 0096); leave `Mod+Q` free for the
  operator.
- **Drop KDE's `Alt+F4`** in favour of only Meta+X — rejected: `Alt+F4` is a
  deep cross-platform reflex; keeping both costs nothing.

## Consequences

- One close key everywhere; muscle memory transfers across sessions on the
  combined host.
- The change is config-only (three seeded files), no package or code change.
- Stock/pure environments (ADR 0112) seed **no** keybinds, so Meta+X is a
  full-environment feature only: a pure KDE closes with upstream `Alt+F4`, a
  pure compositor with its own default (`Mod+Q`).
