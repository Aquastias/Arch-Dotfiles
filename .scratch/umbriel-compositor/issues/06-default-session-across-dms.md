# 06: Default Session across display managers + Guided marker

**What to build:** On a multi-desktop host, a fresh login preselects the
Default Session, `environment.desktop[0]`. The next pick the operator makes
at the greeter is remembered over it, so it is never a lock. Every Display
Manager Adapter seeds it as the remembered last session:
- noctalia-greeter: `[session].last`, never `[session].default`
- greetd + tuigreet: its remember-session cache; verify the current format
  upstream before writing
- SDDM: `state.conf` `[Last] Session=`

The value is the identity each DM matches sessions on. No seed for an empty
desktop set. Those state paths must survive impermanence rollback. The
Guided desktop row and profile preview mark the first entry `(default)`.
Independent of Umbriel: provable with KDE/niri/Hyprland.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] DM adapter bats (seed-root seam) per DM: multi-desktop seeds
      `desktop[0]`, single-desktop no regression, empty set seeds nothing
- [x] Impermanence: seeded state survives rollback on all three DMs
- [x] Guided replay shows the `(default)` marker on the first pick and in
      the profile preview
- [ ] VM: a host with `niri` first lands on niri at first login; picking
      another session is remembered on next login

Spec: ../PRD.md · ADR 0091, 0158, 0159 · glossary: Default Session

## Comments

- Impermanence: all three state paths live under `/var` (not a Rollback
  Dataset), so they survive rollback with no persist entry.
- VM first-login check deferred to ticket 07's Audit Run (desktop/laptop land
  on Umbriel), per the one-VM-at-a-time rule.
