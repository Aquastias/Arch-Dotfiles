Status: ready-for-agent

# Promote config-hungry packages to Host Programs

## Parent

ADR 0089 (`docs/adr/0089-promote-config-hungry-packages-to-programs.md`).
Grounded per `docs/agents/arch-wiki.md` and `.os/programs/PROGRAM_SPEC.md`.

## Problem Statement

Some packages the installer pacstraps need machine state beyond their payload —
a service enabled, a timer running, a config toggled — but as bare
`packages.repo` entries in Host Core **nothing ever runs that setup**. They are
installed and silently left under-configured, unlike a Program (e.g. `searxng`,
`cups`) whose `install.sh` performs its setup. `ccache` is the archetype: it is
installed, but `/etc/makepkg.conf` still has `!ccache`, so it never caches a
single build.

## Solution

Promote the config-hungry packages from bare `packages.repo` lines into
`kind: host` Programs under `programs/<category>/<name>/`, so each one's
`install.sh` owns **both** its package install and its setup (single home, per
ADR 0089 — the same boundary ADR 0079 drew for `cups`). Wire them as
unconditional base Programs on every real host via Host Core `host_programs`.
Packages that install and work with no further state stay bare in
`packages.repo`.

Four packages qualify from the current Host Core lists (each verified against
its Arch Wiki page):

- **ccache** — `/etc/makepkg.conf` `BUILDENV=(… !ccache …)` → `ccache`.
  (Arch Wiki: ccache.)
- **reflector** — enable `reflector.timer` (weekly); ship the package's default
  `/etc/xdg/reflector/reflector.conf`. Enabling *both* the service and the timer
  is redundant — timer only. (Arch Wiki: Reflector.)
- **smartmontools** — enable `smartd.service`; the shipped `/etc/smartd.conf`
  `DEVICESCAN -a` default monitors every disk. (Arch Wiki: S.M.A.R.T.)
- **fwupd** — enable `fwupd-refresh.timer` (metadata refresh + MOTD firmware
  notices); not enabled by default on Arch, and useful on a bare-WM (Hyprland)
  install where no graphical updater coordinates firmware. (Arch Wiki: fwupd.)

`logrotate` was evaluated and **rejected**: `logrotate.timer` is already enabled
by default on Arch (a `/usr` symlink), so a Program would be empty.

## User Stories

1. As an operator, I want `ccache` actually enabled in `/etc/makepkg.conf` after
   install, so that repeated AUR/`makepkg` rebuilds are cached without me hand-
   editing config.
2. As an operator, I want `reflector.timer` running after install, so that my
   mirror list is refreshed weekly without manual `reflector` invocations.
3. As an operator, I want `smartd.service` enabled after install, so that disk
   SMART failures are monitored from first boot.
4. As an operator on a Hyprland (no graphical updater) install, I want
   `fwupd-refresh.timer` enabled, so that I am notified of firmware updates at
   the console.
5. As a maintainer, I want each promoted package to have exactly one home (its
   Program folder), so that its install and its setup can never drift apart
   across two files.
6. As a maintainer reading `hosts/core/profile.jsonc`, I want the promoted
   packages absent from `packages.repo` and present in `host_programs`, so that
   the package's new home is obvious from the config.
7. As a maintainer, I want the promoted Programs to run on every real host
   unconditionally, so that the workstation base is consistent without a per-host
   opt-in.
8. As a maintainer of the lean VM fixtures, I want the promoted Programs excluded
   from `arch-kde` / `arch-secure` / `arch-data`, so that the test fixtures stay
   minimal exactly as they already opt out of Host Core packages.
9. As an operator using the Guided Installer, I want the promoted Programs to
   never appear in a program picker, so that unconditional base software is not
   presented as an optional choice (preserving ADR 0086's empty host-programs
   row).
10. As a maintainer, I want a `Core-Owned Program` concept parallel to
    `Menu-Owned Program`, so that a Program whose sole home is Host Core is
    filtered from the pickers the same way control-owned Programs are.
11. As a maintainer, I want each Program authored to `PROGRAM_SPEC.md`, so that
    package sourcing (`pacman`, `kind: host`), service declaration
    (`system_services`), and header comments follow the house contract.
12. As a maintainer, I want every package name and config value traced to the
    package's Arch Wiki page, so that the repo matches upstream and does not
    drift on memory (per `docs/agents/arch-wiki.md`).
13. As a maintainer, I want the promotion recorded as an ADR, so that a future
    reader who wonders why `ccache`/`reflector`/`smartmontools`/`fwupd` vanished
    from `packages.repo` finds the rationale.
14. As a maintainer running the test suite, I want the config-resolution tests
    updated to reflect the four packages moving from `packages.repo` to
    `host_programs`, so that the suite stays green and encodes the new shape.

## Implementation Decisions

- **Four new Program folders**, all `kind: host` (root-owned: they write under
  `/etc` and enable system units, installed via `pacman`, run before user
  programs):
  - `programs/dev/ccache/` (new `dev` category)
  - `programs/system/reflector/`
  - `programs/system/smartmontools/`
  - `programs/system/fwupd/`
- **Single home (ADR 0089).** Each Program's `install.sh` installs its own
  package via `pacman -S --noconfirm --needed`; the four names are removed from
  Host Core `packages.repo` (`ccache` from the `dev` group; `reflector`,
  `smartmontools`, `fwupd` from the `system` group).
- **Setup per Program:**
  - `ccache` — `install.sh` edits `/etc/makepkg.conf` to enable the `ccache`
    `BUILDENV` flag (append-after-delete idiom, so it converges whether the line
    is `!ccache` or already `ccache`). No `system_services`.
  - `reflector` — `config.jsonc` declares `system_services: ["reflector.timer"]`;
    `install.sh` installs the package and leaves the shipped `reflector.conf`
    untouched. Service is NOT enabled (redundant with the timer).
  - `smartmontools` — `config.jsonc` declares
    `system_services: ["smartd.service"]`; default `/etc/smartd.conf` is left as
    shipped. Directory name matches the package (`smartmontools`); the unit is
    `smartd.service`.
  - `fwupd` — `config.jsonc` declares
    `system_services: ["fwupd-refresh.timer"]`; default config left as shipped.
- **Service enablement is declarative.** Prefer `system_services` in
  `config.jsonc` (the Runner enables them in-chroot) over `systemctl enable` in
  `install.sh` — the units ship with their packages.
- **Unconditional base wiring.** Add all four names to Host Core `host_programs`.
  These become the first **free-standing, unconditional** Host Programs (neither
  toggle-derived nor secrets-activated) — a new sub-kind.
- **VM opt-out.** `host_programs` is additive and `packages.inherit: false` only
  drops packages, so the three VM fixtures would otherwise inherit and run these.
  Each VM fixture (`arch-kde`, `arch-secure`, `arch-data`) gets the four names in
  `host_programs_exclude`, mirroring how the fixtures already opt out of Host
  Core packages. The layer-resolver strips `host_programs_exclude` from the
  resolved profile after applying it (existing behaviour).
- **Core-Owned Program filter.** The Guided Installer program pickers show
  `kind: host` programs minus `menu_owned_programs`. The four are not
  control-owned, so without a filter they would resurface in the host picker and
  re-break ADR 0086's "Packages lists no Programs." Add a new
  `core_owned_programs()` set (the four names) in `lib/config/menu-owned.sh`, and
  have `_ctl_host_program_names` / `_ctl_user_program_names` subtract it
  *alongside* `menu_owned_programs`. `menu_owned_programs` stays semantically
  "control-owned" (its union test is untouched).
- **Docs.** ADR 0089 already written. `CONTEXT.md`: add a `Core-Owned Program`
  glossary term (sole home is Host Core; parallel to `Menu-Owned Program`), and
  correct the existing "every `kind: host` program is Menu-Owned" statement to
  "Menu-Owned *or* Core-Owned."

## Testing Decisions

Good tests here assert **external behaviour at the highest existing seam** — the
resolved Effective Config and the picker option sets — not internal wiring.
Reuse existing seams only; no new seam is introduced.

- **Config resolution seam** (`load_profile` → layer-resolver), prior art in
  `tests/config/layered-profiles.bats`:
  - The four names are absent from resolved `packages.repo` on desktop/laptop and
    present in resolved `host_programs`.
  - The VM fixtures resolve with the four absent from `host_programs` (excluded)
    and continue to resolve lean (`packages.repo == {}`).
  - Update `tests/config/layered-profiles.bats` "core packages reach both
    machines" to drop `fwupd` (now a Host Program, not a repo package).
- **Picker filter seam**, prior art in `tests/config/guided-controller.bats` and
  `tests/config/guided-menu.bats`:
  - `_ctl_host_program_names` excludes the four (Core-Owned); the `host_programs`
    menu row stays absent.
  - `core_owned_programs()` returns exactly the four (parallel to the existing
    `menu_owned_programs` union assertion at `guided-controller.bats:201`).
- **Registry/audit seam** (auto), prior art `tests/audit.sh`: the four folders
  are `kind: host`, carry `config.jsonc` + `install.sh`, and their
  `host_programs` references resolve.

## Out of Scope

- `install.sh` bodies are not bats-tested — this repo does not unit-test chroot
  install scripts (`packages.bats` explicitly excludes system-bound code). The
  ccache `makepkg.conf` edit and service enablement are exercised by VM
  integration runs (`tests/vm/*.log`), not unit tests. (Confirmed with the
  operator: the ccache transform is NOT pulled into a separate pure function.)
- `logrotate` (already-enabled timer), `sbctl` (Secure-Boot coupling, risky),
  `nvm` (shell integration — dotfiles' concern), `speech-dispatcher`, and
  `vscodium-marketplace` are not promoted in this pass.
- No new Guided Installer toggle/menu control for the four — they are
  unconditional base, not user-selectable.
- Reflector's runtime `--country` is NOT plumbed from the installer's Mirror
  Countries selection; the shipped rate-ranked default is accepted.

## Further Notes

- All four are `kind: host` because setup touches `/etc` and system units and
  needs root; they install via `pacman`, not `paru` (all four are official repo
  packages).
- `reflector` is also used by the installer itself on the ISO
  (`install_base`); that is unrelated to the target system's promoted
  `reflector` Program and needs no coordination.
- Grounding sources: Arch Wiki pages for ccache, Reflector, S.M.A.R.T., fwupd,
  Logrotate (the last confirming `logrotate.timer` is already enabled).
