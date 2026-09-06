# Stock (pure) environment variants — bare KDE / Hyprland / niri

---
Status: accepted. Adds `environment.stock` (bool, default `false`). Generalises
ADR 0097's `wayland_shell: none` ("truly bare compositor, seeding nothing") to a
single cross-desktop lever and extends it to KDE, which had no bare mode.
Threaded to the chroot like `ENVIRONMENT_WAYLAND_SHELL` (ADR 0090). Committed
`*-pure` profiles model the ADR 0034/minimal shape (`packages.inherit: false`).
---

The installer's KDE and wlroots adapters install an **opinionated** environment:
KDE pulls the curated app set + KDE-config seed (ADR 0087/0088/0111); niri and
Hyprland layer the Noctalia work shell + seeded configs (ADR 0097). The operator
wants the opposite option too — install **upstream stock**: the Plasma shell or
the bare compositor with **no dotfiles, no extra apps, no Noctalia** — the
distro's own defaults, to build up from scratch. Compositors already had half of
this (`wayland_shell: none` seeds nothing), but KDE had no equivalent and there
was no single, discoverable "give me stock" control.

## Decision

**Add `environment.stock` (bool, default `false`).** When `true`, every selected
desktop installs upstream-stock:

- **KDE** → the `plasma-meta` shell only. Skip `apps_list` / `apps_extra` /
  `plugins` / `aur` (ADR 0087) **and** the ADR 0088/0111 DE-config seed. Result:
  stock Breeze, first-run, no octopi/qt6ct, no captured settings.
- **niri / Hyprland** → bare compositor + session, no Noctalia, no seeded
  configs or keybinds — i.e. `stock` forces the ADR 0097 `wayland_shell: none`
  path (an explicit `wayland_shell` still validates; `stock` guarantees it).

`stock` threads into the chroot as `ENVIRONMENT_STOCK`, read by the adapters —
no runner change, mirroring `ENVIRONMENT_WAYLAND_SHELL` (ADR 0090). Host-level
daemons are **not** DE config and stay on their own toggles: bluetooth
(default-on, ADR 0080) still installs and enables regardless of `stock`.

**Exposure — two seams over one lever (ADR 0036's three-front-end rule):**

1. **Guided Installer** — a `stock` [[Cycle Field]] in the Environment category
   (bare bool, flips in place — ADR 0075), default off.
2. **Committed profiles** `kde-pure`, `hyprland-pure`, `niri-pure` — each
   modelled on `minimal` (`packages.inherit: false`, `host_programs: []`), a
   single `environment.desktop`, and `environment.stock: true`. So "install pure
   X" is a `--profile X-pure` away, and the same state is reachable in guided.

## Considered options

- **A per-desktop `full|pure` modifier** on the `environment.desktop` array —
  rejected: `desktop` is a flat multi-select; a parallel per-element variant
  complicates the schema and the menu. A pure install is single-desktop in
  practice; a global bool is simpler and covers it.
- **Committed profiles only, no guided control** — rejected: violates the
  one-capability-reachable-from-every-front-end rule (ADR 0055/0086).
- **Reuse only `wayland_shell: none`, leave KDE opinionated** — rejected: KDE is
  half the ask; it needs a bare mode too. `stock` unifies both.
- **A new top-level key outside `environment`** — rejected: it is an environment
  property; it belongs beside `desktop` / `wayland_shell`.

## Consequences

- Three genuinely stock installs are first-class and testable, without deleting
  the opinionated default.
- `stock` and an explicit `wayland_shell: noctalia` are contradictory; the
  resolver treats `stock` as authoritative for the selected desktops (documented
  at the validation site).
- The Package Resolver must report the stock reduction (no app/seed sets) so
  `explain-packages` and the guided `derived` view stay truthful (ADR 0056).
- Adding stock is additive: the adapters branch on `ENVIRONMENT_STOCK`; no
  runner or dispatch change (ADR 0090's "new DE = new dir" property is kept).
