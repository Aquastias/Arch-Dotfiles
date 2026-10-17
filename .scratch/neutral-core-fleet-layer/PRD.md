# PRD: Neutral core; personal software in the Fleet Layer

Status: ready-for-agent

Anchored by [[ADR 0157]]. Partly supersedes [[ADR 0114]] and the personal
Guided Launch Presets of [[ADR 0055]] / [[ADR 0154]]; amends [[ADR 0112]].

## Problem Statement

Over time the operator added more and more personal settings and programs —
dev toolchain, gaming, claude, pi, searxng, docker, curated KDE/Noctalia,
nerd fonts, secure extras, their own hostname, user, timezone, mirrors. All
of it sits in Host Core, User Core and the Guided Launch Presets, so it is the
default for **anyone**. Someone who runs the Guided Installer and never picks
the `desktop` or `laptop` Host Profile still gets the operator's personal
machine.

Worse, picking a non-fleet profile in Guided does not install what that
profile says: picking `minimal` or a `*-pure` profile still installs the 105
Host Core packages and the secure Security & Backup Extras, because the pick
overlays the profile on the Host Core baseline (and on any earlier pick).
`install.sh --profile minimal` installs neither — the two front-ends disagree.

The `*-pure` profiles also declare the `aquastias` user, so a "stock" install
still lands claude, pi, docker, vscodium, teamspeak3 and the rest.

Finally, the operator cannot see the whole install set: `explain-packages`
omits Host Programs and User Programs.

## Solution

Whatever the operator chooses in the Guided menu is what gets installed, and
nothing personal is chosen for them. A committed Host Profile installs exactly
what it declares, identically through `install.sh --profile` and the Guided
Profiles picker.

The operator's personal software moves into a new **Fleet Layer** that only
`desktop` and `laptop` fold (Host Core → Fleet Layer → host). Host Core and
User Core become neutral. Schema Install Defaults and Guided Launch Presets
become neutral. Picking a profile in Guided re-baselines the session on that
profile. `desktop` and `laptop` resolve to exactly the same install as today.

## User Stories

1. As a guest operator, I want a blank Guided session to preselect no
   personal software, so that I install only what I choose.
2. As a guest operator, I want no desktop preselected, so that a desktop is
   installed only if I pick one.
3. As a guest operator, I want the hostname to default to `archlinux`, so that
   my machine is not named after the operator's desktop.
4. As a guest operator, I want no user preselected, so that I never get the
   operator's account, groups, sudo or git identity.
5. As a guest operator, I want Proceed to block until I have created a user,
   so that I cannot install a machine with no login.
6. As a guest operator, I want my timezone autodetected, so that I do not
   inherit `Europe/Bucharest`.
7. As a guest operator, I want Security & Backup Extras off by default, so
   that firewalld, antivirus, rootkit checks, AppArmor, borg and
   zfs-auto-snapshot land only if I enable them.
8. As a guest operator, I want a picked desktop to default to stock, so that I
   get the distro's own KDE / niri / Hyprland, not the operator's curated
   apps, captured settings, Noctalia shell and theme.
9. As a guest operator, I want to opt into the curated environment via the
   existing `stock` Cycle Field, so that I can still have it if I want it.
10. As a guest operator, I want the default font selection to be neutral
    (noto, dejavu, liberation), so that nerd fonts and ttf-ms-fonts land only
    if I tick them.
11. As a guest operator, I want mirrors ranked worldwide by default, so that I
    do not inherit the operator's country list.
12. As a guest operator, I want printing, bluetooth and power services still
    on by default, so that a generic machine works out of the box.
13. As a guest operator, I want a user I create in Guided to inherit only a
    neutral User Core (bash, no programs), so that no personal userland comes
    with it.
14. As a guest operator, I want the Host Package List to start empty, so that
    only the Base Package List and what my choices derive get installed.
15. As an operator, I want picking a profile in Guided to install exactly what
    `install.sh --profile <name>` would, so that the two front-ends never
    disagree.
16. As an operator, I want picking `minimal` in Guided to install no Host Core
    or Fleet Layer packages, so that a bare box stays bare.
17. As an operator, I want picking a profile to drop everything from an
    earlier pick or edit, so that picking `desktop` then `minimal` leaves no
    `desktop` residue.
18. As an operator, I want a profile pick to render with no ● override marks,
    so that the profile's values read as the baseline and my later edits
    stand out.
19. As an operator, I want `desktop` and `laptop` to resolve to exactly the
    same Effective Config and install set as before, so that my machines do
    not change.
20. As an operator, I want all my fleet software in one Fleet Layer, so that
    adding a fleet package is a one-line edit shared by both machines.
21. As an operator, I want the Fleet Layer to carry `stock: false`, the full
    font set and my mirror countries, so that my machines keep the curated
    environment.
22. As an operator, I want the Fleet Layer hidden from the Profiles picker, so
    that nobody installs a layer as if it were a machine.
23. As an operator, I want `install.sh --profile fleet` rejected, so that the
    layer cannot be installed by itself.
24. As an operator, I want my personal User Programs and zsh shell on
    `aquastias`, so that they follow my account and not every user.
25. As an operator, I want a second human user to declare their own programs,
    so that they get a neutral starting point.
26. As an operator, I want the `*-pure` profiles to use a neutral user, so
    that a stock install carries no personal userland.
27. As an operator, I want stock KDE to be `plasma-meta` plus the display
    manager and its strict needs, so that papirus, breeze-gtk and the weather
    widget do not leak into a stock install.
28. As an operator, I want `minimal` to stay the bare TTY install it is today,
    so that the canonical headless example still holds.
29. As an operator, I want `explain-packages` to report Host Programs and each
    user's programs, so that "what lands on this machine?" is fully answered.
30. As an operator, I want the Guided derived package section to agree with
    `explain-packages`, so that the menu and the tool never drift.
31. As an operator, I want the curated VM fixtures to keep testing the curated
    environment, so that flipping the stock default does not silently turn
    them stock.
32. As an operator, I want the VM throwaway users' now-vacuous exclusions
    removed, so that fixtures do not exclude what nothing inherits.
33. As an operator, I want a regression test that a blank Guided session holds
    nothing from the Fleet Layer or `aquastias`, so that a future addition to
    core cannot re-leak.
34. As an operator, I want a regression test that every committed profile
    yields the same Effective Config through Guided and `--profile`, so that
    the front-ends stay in lockstep.
35. As an operator, I want a regression test that `desktop` and `laptop`
    still resolve to the same set as each other, so that the [[ADR 0114]]
    invariant survives the move.
36. As an operator, I want Host Core, User Core, Fleet Layer and the pure
    profile entries in CONTEXT.md to match the new layering, so that the
    glossary stays truthful.
37. As an AFK agent, I want the golden capture taken before any move, so that
    the no-regression check compares against the true baseline.

## Implementation Decisions

- **Fleet Layer** — a new host-kind layer folded by the Layer Resolver
  between Host Core and the host. Only `desktop` and `laptop` fold it. It is
  a layer, not an installable Host Profile: the Profiles picker's enumeration
  excludes it (like `core` and `vm/`) and the Profile Loader rejects it as a
  `--profile` target. Mechanism for "only these two fold it" is the
  implementer's choice (an explicit layer list in the Profile Loader is
  simplest); the Layer Resolver already folds N layers, so its fold is
  unchanged.
- **Fleet Layer contents** — everything Host Core carries today except
  `vm.swappiness`: the whole Host Package List (repo + AUR), the base Host
  Programs (ccache, fwupd, gamemode, lact, nix, smartmontools),
  `environment.stock: false`, the full Font Catalog selection (today's
  default-checked set), and the mirror country list. The secure Security &
  Backup Extras already live in `desktop`/`laptop` and stay there.
- **Neutral Host Core** — `vm.swappiness` and `users: []` only.
- **Neutral User Core** — shell `/bin/bash`, today's generic groups, `sudo:
  false`, no programs. `users/aquastias` gains today's User Core programs
  (zsh, kitty, lazygit, yazi, virt-manager, podman, searxng, pi, claude, nvim
  — order preserved for Program Dependency resolution) and `/bin/zsh`.
- **Schema Install Defaults** (the Install Config schema is the one owner,
  [[ADR 0154]]): `stock` → `true`; `mirror_countries` → empty, meaning
  reflector ranks worldwide; the Font Catalog's default-checked set → noto,
  dejavu, liberation. All other Install Defaults unchanged.
- **Reflector with no countries** — the Mirror Service must emit a valid
  worldwide ranking when the country list is empty (no `--country`).
- **Neutral Guided Launch Presets** — hostname `archlinux`; no Primary User
  preset; timezone left to the [[ADR 0118]] autodetect; `environment.desktop`
  empty; Security & Backup Extras absent (off). The fonts preset follows the
  new catalog default.
- **No-user Proceed gate** — Proceed refuses with a clear notice while the
  session has no user. Applies to the interactive controller and the
  headless replay alike.
- **Profile pick re-baselines** — one function in the Profiles module
  replaces `profiles_seed`'s overlay: it resolves the picked profile through
  the same layers the Profile Loader uses (Host Core → Fleet Layer when
  applicable → host), installs that as the session baseline, and clears the
  Config State override map and session side-state (the same reset the
  `＋ New host` row performs). Both the interactive Profiles screen and the
  headless replay call it, removing the duplicated resolve-then-seed logic.
- **Equivalence contract** — for every committed Host Profile, the Guided
  Effective Config after a pick equals the `--profile` Effective Config,
  ignoring device paths and secrets.
- **Pure profiles** — `kde-pure`, `niri-pure`, `hyprland-pure` switch to a
  neutral user (reuse `server` or add a neutral desktop user; implementer's
  choice, documented in the profile header). `stock: true` becomes redundant
  with the new default but stays explicit.
- **Stock KDE package set** — the stock adapter path installs `plasma-meta`,
  the display manager and only what they strictly need; papirus, breeze-gtk
  and the weather widget move to the curated path. The Package Resolver's
  stock KDE report follows.
- **Package Resolver** — gains Host Program and per-user User Program
  sources (each tagged so `--sources` shows them), resolving each program to
  the packages it installs. `explain-packages` and the Guided derived section
  share it.
- **VM fixtures** — curated fixtures (`arch-kde`, `arch-niri`,
  `arch-hyprland`, `arch-combined*`, `arch-audit`) set `stock: false` and,
  where they rely on them, the full fonts and Noctalia shell. Throwaway VM
  users drop their `programs_exclude` of former User Core programs.
- **Docs** — CONTEXT.md: Host Core, User Core, Root Shell, Font Catalog,
  Mirror Service, Guided Launch Preset, Pure (Stock) Profiles entries updated;
  the new Fleet Layer entry already exists. Profile header comments in Host
  Core and the fleet hosts updated.

## Testing Decisions

- A good test asserts external behaviour at the highest seam — the Effective
  Config a front-end produces, or the install set the Package Resolver
  reports — never how the layers are stitched internally.
- **Seam 1 — Effective Config.** `--profile` via the Profile Loader's
  assemble path vs Guided via the headless replay (answers file →
  `guided_build` → emit). Tests:
  - every committed Host Profile: Guided pick ≡ `--profile`, devices and
    secrets masked;
  - blank replay (with a user created): no package, Host Program or User
    Program from the Fleet Layer or `aquastias`; hostname `archlinux`; no
    desktop; extras off; `stock` true;
  - pick `desktop` then `minimal`: result equals a fresh `minimal` pick;
  - Proceed with no user is refused.
- **Seam 2 — install set.** The Package Resolver / `explain-packages`:
  - one-off golden diff: capture `desktop` and `laptop` resolved sets (and
    Effective Configs) before the move, assert identical after — the first
    slice;
  - permanent: `desktop` ≡ `laptop` install set; `minimal`, `*-pure` and the
    blank Guided set share nothing with the Fleet Layer's packages/programs;
  - Host Program and User Program sources appear in `--sources`.
- **Lower-level bats** are only edited where their assertions now contradict
  [[ADR 0157]] (e.g. guided-seed's eterniox / aquastias / secure-baseline /
  Host Core packages cases; guided-profiles' overlay semantics; personal
  profiles' "discord from core").
- **Prior art:** `tests/explain-packages.bats` (resolver via the tool),
  `tests/config/personal-profiles.bats` (resolved committed profiles),
  `tests/config/guided-seed.bats` and `guided-profiles.bats` (seed and pick),
  `tests/guided/shell-consent-and-users.bats` (headless replay with a
  profile), `tests/config/layer-resolver.bats` / `layered-profiles.bats`
  (multi-layer folds).
- **VM:** one curated fixture (e.g. `arch-kde`) installs unchanged, and a
  blank Guided VM install with one desktop lands stock — verified in the VM
  per the VM agent workflow.

## Out of Scope

- Changing what `desktop` / `laptop` install — they must resolve identically.
- A user-side fleet layer or host-aware user programs.
- Neutralising generic Install Defaults (zfs, lts, systemd-boot, multilib,
  pacman cosmetics, encryption/ssh/impermanence off).
- Changing the printing, bluetooth or power service defaults.
- The stow-side dotfiles (`stow-configs.sh`) — only the installer's layers.
- Secrets posture ([[ADR 0055]]'s default passwords) — unchanged.

## Further Notes

- The leak in the Guided pick is live today; the first slice (golden capture
  + re-baseline fix) closes it before the bigger move.
- Picking `desktop` in Guided must still reproduce the full personal machine
  — the Fleet Layer is folded by the pick path exactly as by `--profile`.
