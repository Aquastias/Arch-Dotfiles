# 02: Bare Umbriel installs and boots (`umbriel-pure`)

**What to build:** The operator can install upstream-stock Umbriel with
`install.sh --profile umbriel-pure`, or through the Guided Installer
(desktop row + `stock` Cycle Field), and log into an Umbriel session.

- `umbriel` joins the closed `environment.desktop` enum and the wlroots set
  (01).
- A new core-only Umbriel Desktop Environment Adapter. It declares
  `umbriel-git` and `xdg-desktop-portal-umbriel-git` (+ the fleet theming
  deps) in its adapter AUR list, installed by the vetted paru pass.
- It enables seatd + the `seat` group, idempotent beside Hyprland. The
  session appears once in every display manager's list.
- A pure Umbriel package map is shared by the adapter and the Package
  Resolver.
- An `umbriel-pure` Stock Profile modelled on `niri-pure`, seeding nothing,
  so Umbriel uses its packaged config.

Grounding: upstream docs (no Arch Wiki page), per ADR 0159.

**Blocked by:** 01

**Status:** done

- [x] Unknown desktop values still rejected; `umbriel` accepted
- [x] Adapter bats (seed-root seam): seatd enabled, session listed once,
      nothing seeded under stock
- [x] Resolver reports the Umbriel packages from the shared map
- [x] pure-profiles + Guided profile-equivalence cover `umbriel-pure`
- [x] VM: `umbriel-pure` installs, greeter offers Umbriel, session starts
- [x] Installer README/REFERENCE desktop lists mention Umbriel

Spec: ../PRD.md · ADR 0159
