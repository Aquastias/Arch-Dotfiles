# 03 — Promote reflector, smartmontools, fwupd to Host Programs

**What to build:** After install, three self-configuring services are live —
`reflector.timer` refreshes mirrors weekly, `smartd.service` monitors disk SMART
health from first boot, and `fwupd-refresh.timer` provides firmware metadata
refresh + MOTD notices (useful on a bare-WM Hyprland install with no graphical
updater). Promote all three from bare `packages.repo` entries into `kind: host`
Programs under `programs/system/*` (single home, ADR 0089); each installs its own
package and declares its unit in `system_services` so the Runner enables it. They
run unconditionally on every real host and never appear in a Guided picker. Each
grounded on its Arch Wiki page (Reflector, S.M.A.R.T., fwupd) per
`docs/agents/arch-wiki.md` and authored to `PROGRAM_SPEC.md`.

**Blocked by:** 02 — Promote ccache (shares `hosts/core/profile.jsonc`, the VM
fixtures, `core_owned_programs`, and `layered-profiles.bats`; serialized to stay
green).

**Status:** done

- [x] `programs/system/reflector/`, `programs/system/smartmontools/`, and
      `programs/system/fwupd/` each exist with `config.jsonc` (`kind: host`) and
      `install.sh`, matching `PROGRAM_SPEC.md`.
- [x] Each `install.sh` installs its package via `pacman --needed`; the shipped
      default config is left untouched (reflector.conf, smartd.conf, fwupd).
- [x] `config.jsonc` declares `system_services`: `["reflector.timer"]` (timer
      only — service is redundant), `["smartd.service"]`, and
      `["fwupd-refresh.timer"]` respectively.
- [x] All three removed from Host Core `packages.repo` (`system` group) and added
      to Host Core `host_programs` and `core_owned_programs`.
- [x] All three added to `host_programs_exclude` in the `arch-kde`,
      `arch-secure`, and `arch-data` VM fixtures.
- [x] `fwupd` is dropped from the `layered-profiles.bats` "core packages reach
      both machines" repo assertion (now a Host Program).
- [x] Config-resolution tests assert the three are absent from resolved
      `packages.repo` and present in resolved `host_programs` on desktop/laptop,
      and absent from the VM fixtures' resolved `host_programs`.
- [x] `core_owned_programs` test asserts it contains all three.
- [x] `tests/audit.sh` passes for the three folders; full bats suite green.

## Comments

- 2026-09-27 doc sync: shipped in ef5f24a, ce126da, 39ca93f, 484aa2b, 23200d7
  (ADR 0089); Core-Owned Program filter later removed in c1d30d0.
