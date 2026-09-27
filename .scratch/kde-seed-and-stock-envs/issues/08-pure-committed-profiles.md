# 08 — `*-pure` committed profiles

**What to build:** Three committed [[Host Profile]]s — `kde-pure`,
`hyprland-pure`, `niri-pure` — so `install.sh --profile <name>-pure` installs a
stock environment unattended: a single desktop, `environment.stock: true`, and
the bare-userland shape of `minimal` (`packages.inherit: false`,
`host_programs: []`). (ADR 0112.)

**Blocked by:** 04 (stock KDE adapter), 05 (stock compositor adapters), 06
(resolver reduction — so the profiles' reported package set is truthful).

**Status:** done

- [x] `.installer/hosts/kde-pure`, `hyprland-pure`, `niri-pure` exist, each with
      one `environment.desktop`, `environment.stock: true`,
      `packages.inherit: false`, `host_programs: []`, modelled on `minimal`.
- [x] Each validates against the closed schema and resolves (over Host Core) to a
      single-desktop, stock, no-inherit config.
- [x] `tests/vm/profile-validate.bats` covers all three.
- [x] The resolver / `explain-packages` report each profile's reduced set (stock
      shell/compositor only, no apps, no Noctalia).
- [x] Each profile appears in the Guided Installer Profiles picker like any other
      committed profile.

## Comments

- 2026-09-27 doc sync: shipped in 6dfb331, 3918ff4, b34e8da, 11d0e5c, 96de292,
  577586f (ADR 0111-0115).
