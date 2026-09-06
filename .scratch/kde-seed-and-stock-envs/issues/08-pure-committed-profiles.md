# 08 — `*-pure` committed profiles

**What to build:** Three committed [[Host Profile]]s — `kde-pure`,
`hyprland-pure`, `niri-pure` — so `install.sh --profile <name>-pure` installs a
stock environment unattended: a single desktop, `environment.stock: true`, and
the bare-userland shape of `minimal` (`packages.inherit: false`,
`host_programs: []`). (ADR 0112.)

**Blocked by:** 04 (stock KDE adapter), 05 (stock compositor adapters), 06
(resolver reduction — so the profiles' reported package set is truthful).

**Status:** ready-for-agent

- [ ] `.installer/hosts/kde-pure`, `hyprland-pure`, `niri-pure` exist, each with
      one `environment.desktop`, `environment.stock: true`,
      `packages.inherit: false`, `host_programs: []`, modelled on `minimal`.
- [ ] Each validates against the closed schema and resolves (over Host Core) to a
      single-desktop, stock, no-inherit config.
- [ ] `tests/vm/profile-validate.bats` covers all three.
- [ ] The resolver / `explain-packages` report each profile's reduced set (stock
      shell/compositor only, no apps, no Noctalia).
- [ ] Each profile appears in the Guided Installer Profiles picker like any other
      committed profile.
