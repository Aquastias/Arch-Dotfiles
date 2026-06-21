# Guided Installer — UX redesign (two-level menu + host Security/Backup)

Status: ready-for-agent

Decision of record: **ADR 0041** (host security/backup tooling installed
via the Primary User's paru pass). Builds on ADR 0039 (Guided Installer,
profile-optional front-end), 0040 (Filesystem Adapter axis), 0036
(unified profile / Effective Config), 0007 (Host Core carries no package
list), 0002 (system flag host-owned), 0025 (secrets-activated sops).

Glossary: Guided Installer, Configuration Categories, Config State,
Security & Backup Extras, Primary User, Host Profile, Host Core, Effective
Config, System Program, User Program, Program Install Script, Runner,
Pre-Install Picker, Sysctl Defaults, Categorized List.

## Problem Statement

The Guided Installer works but is unpleasant to drive. Every menu row is
prefixed with its section name (`Disks · …`, `Advanced · …`, `Options ·
…`), so the same word repeats down the whole screen and the list reads as
noise rather than structure. The toolbar actions (Undo, Redo, Reset,
Proceed, Save, Export) sit in the same flat fzf list as the config rows
and are visually indistinguishable from them — there is no separation
between "things I configure" and "things I do".

Several fields are wrong or misplaced. `sysctl` has the weight of a
top-level action despite being a niche tweak. The Users row shows empty
even though there is an obvious default operator (`aquastias`). The disk
layout has no obvious default. Hostname defaults to nothing. There is a
"dotfiles repo URL" field that makes no sense to set from the installer.
Security and backup are reduced to two opaque booleans (`security extra:
false`) that point at extras scripts which were never shipped — there is
no way to actually choose which firewall / antivirus / rootkit scanner /
snapshotting you get.

And the surface is plain: a flat fuzzy list that does not feel like an
installer.

## Solution

Restructure the Guided Installer into a **two-level menu** of
**Configuration Categories**. The top level lists eight categories with a
short summary of what each configures (`Security — firewall, antivirus,
rootkit`); pressing Enter drills into that category's fields. A section
name never repeats per row. A category row shows a `●` when any field
inside it has been overridden, so the operator sees at a glance what
they've touched.

The toolbar is pulled out of the list: the terminal destinations
(Proceed / Save / Export) are selectable rows under a divider at the
bottom, and the edit-history operations (Undo / Redo / Reset
field|section|all) become footer keybindings (`^Z` / `^Y` / `^R`), shown
in the fzf header. The renderer stays **fzf** — no new dependency, and
fzf keeps the disk-picker preview pane.

Defaults are filled in so an untouched run is sensible for this operator:
hostname `eterniox`, Primary User `aquastias`, single-disk ZFS layout,
locale `en_US.UTF-8` / timezone `Europe/Bucharest` / keymap `us`.

`sysctl` moves under Options; the old Pacman section (mirror countries,
multilib) folds into Options; swap / swap-size / esp-size are displayed
under Disks (where the operator expects storage knobs); the dotfiles-repo
field is removed entirely.

Security and Backup become first-class **Configuration Categories**. The
operator picks a single firewall (firewalld / ufw / none — the two
firewalls are mutually exclusive), plus antivirus (clamav), rootkit
scanner (rkhunter) and MAC (apparmor); and snapshotting (zfs-auto-snapshot)
and encrypted backup (borg). A fresh install pre-ticks firewalld + clamav
+ rkhunter + apparmor and zfs-auto-snapshot + borg. These selections are
**Security & Backup Extras** — host-level `post_install.security` /
`post_install.backup` objects installed via the **Primary User's** paru
pass (ADR 0041), because the tools are paru-based User Programs and paru
refuses to run as root.

## User Stories

1. As an operator, I want the menu grouped into named categories instead
   of a flat list, so that I can find what I'm looking for without reading
   a repeated section prefix on every row.
2. As an operator, I want to press Enter on a category and see only that
   category's fields, so that each screen is focused.
3. As an operator, I want a category row to show a `●` when I've changed
   something inside it, so that I can see what I've touched without
   drilling in.
4. As an operator, I want the toolbar actions separated from the config
   rows, so that I can tell "things I configure" apart from "things I do".
5. As an operator, I want Proceed / Save / Export as clearly-grouped rows
   under a divider, so that the terminal actions are obvious and distinct.
6. As an operator, I want Undo / Redo / Reset on keybindings shown in the
   footer, so that editing history is a transient operation, not a menu
   destination.
7. As an operator, I want the hostname to default to `eterniox`, so that I
   don't have to type my usual hostname every install.
8. As an operator, I want `aquastias` pre-selected as the Primary User, so
   that the Users category isn't empty and my account exists by default.
9. As an operator, I want the disk layout to default to `single`, so that
   the common case needs no decision.
10. As an operator, I want locale / timezone / keymap shown under Host with
    sensible defaults (`en_US.UTF-8` / `Europe/Bucharest` / `us`), so that
    I can adjust them but rarely need to.
11. As an operator, I want `sysctl` under Options rather than as its own
    top-level action, so that a niche tweak doesn't have outsized weight.
12. As an operator, I want mirror countries and multilib under Options, so
    that the Pacman knobs live with the other system options.
13. As an operator, I want swap, swap size and ESP size shown under Disks,
    so that storage-sizing knobs are where I expect them.
14. As an operator, I want the dotfiles-repo field gone, so that I'm not
    asked to configure something that makes no sense at install time.
15. As an operator, I want a Security category, so that I can choose which
    hardening tools get installed instead of flipping one opaque boolean.
16. As an operator, I want to pick exactly one firewall (firewalld, ufw, or
    none), so that I never end up with two conflicting firewalls.
17. As an operator, I want firewalld + clamav + rkhunter + apparmor
    pre-ticked on a fresh install, so that a new machine is secured by
    default.
18. As an operator, I want a Backup category with zfs-auto-snapshot and
    borg, so that I can choose my backup posture.
19. As an operator, I want zfs-auto-snapshot + borg pre-ticked, so that a
    new machine has snapshots and a backup tool by default.
20. As an operator, I want the security/backup tools I pick to actually be
    installed, so that the category isn't decorative like the old booleans.
21. As an operator, I want my Security/Backup choices to be host-level and
    independent of which user I add, so that "secure by default" doesn't
    depend on a particular account.
22. As an operator, I want to Save my guided session as a Host Profile that
    records my security/backup choices explicitly, so that re-installing
    via `--profile` reproduces the same secured machine.
23. As an operator, if I remove every user but leave security/backup
    selected, I want the installer to stop and tell me to add a user or
    clear the selections, so that I never get a machine that silently has
    no firewall.
24. As an operator, I want the renderer to stay fast and dependency-free on
    the live ISO, so that the installer always runs without fetching extra
    tools.
25. As a maintainer, I want `aquastias`'s profile to stop hard-pinning the
    security tools now that they're host-owned, so that the Security
    category can actually turn a tool off.
26. As a maintainer, I want a tool listed in both the host selection and a
    user's programs to install once, so that its Program Install Script
    doesn't run twice.
27. As a maintainer, I want the headless replay path and its bats interface
    unchanged, so that the redesign is rendering-plus-fields, not a rewrite
    of the tested cores.
28. As a maintainer, I want the existing bool `post_install` profiles
    migrated to the new object shape, so that the closed schema still
    validates every committed profile.

## Implementation Decisions

**Renderer.** Stay on **fzf** (no new dependency; dialog / whiptail / gum
are not guaranteed on the archzfs-Compatible ISO). fzf is restructured
into a two-level surface and keeps the Pre-Install Picker's preview pane.
The headless replay seam (`--guided <answers>`, keyed) is unchanged — only
interactive rendering and the field/default set change.

**M1 — Menu category model (pure).** Extend the Menu model so the eight
**Configuration Categories** (Host, Disks, Options, Environment, Packages,
Security, Backup, Users) are the contract. New pure functions: one that
returns the ordered categories, each with a summary string and an
`overridden` flag (true when any descendant field is an override); one
that returns the field rows for a single category. The existing per-field
row shape (`{section, field, label, value, overridden}`) is reused as the
per-category drill-in. The display *section* of a field is independent of
its Config State path, so swap/esp can render under Disks while still
writing `options.swap*` / `options.esp_size`.

**Field moves.** `sysctl` → Options; `options.mirror_countries` +
`options.multilib` → Options (the old Pacman section is folded in);
`options.swap` / `options.swap_size` / `options.esp_size` display under
Disks; the `dotfiles_repo` field and its editor are removed. Add
locale / timezone / keymap as editable Host rows over the existing seeds.

**M3 — Guided default seeder (pure).** The launch Config State seeds the
computed defaults: `system.hostname = eterniox`, `users[0] = aquastias`,
single-disk layout, `system.locale = en_US.UTF-8`, `system.timezone =
Europe/Bucharest`, `system.keymap = us`, and the Security/Backup baseline
(below). `aquastias` is emitted explicitly (not a strippable default) —
otherwise the host would have no Primary User.

**Security & Backup Extras schema (ADR 0041).** `post_install.security`
and `post_install.backup` change shape from the old booleans to structured
objects:

- `post_install.security`: `firewall` (`firewalld` | `ufw` | `none`),
  `antivirus` (bool → clamav), `rootkit` (bool → rkhunter), `apparmor`
  (bool).
- `post_install.backup`: `zfs_auto_snapshot` (bool), `borg` (bool).

The closed schema (`profile.sh`), the schema-table accessors
(`accessors.sh`), and the Menu field table (`menu.sh`) migrate from the
bool form to the object form. The back-end default stays **absent = off**
(matching the current `bool false` accessor default), so existing profiles
are unchanged and Save writes the full resolved block explicitly.

**Guided defaults for Security/Backup.** Firewall = `firewalld`; antivirus,
rootkit, apparmor = true; zfs_auto_snapshot, borg = true. Firewall is a
single-choice (radiolist); firewalld and ufw abort if both are present.

**M2 — Post-install resolver (pure).** A new pure core maps a
`post_install.{security,backup}` object to the ordered list of Program
names to install (`firewalld`/`ufw` per the firewall choice, `clamav`,
`rkhunter`, `apparmor`, `zfs-auto-snapshot`, `borg`), produces the
secure-baseline default object, and validates the object's shape (firewall
enum, bool fields).

**M4 — Runner union + dedup (pure fn + wiring).** The Runner unions the
resolved post_install Program names into the **Primary User's** (`users[0]`)
paru pass — the same seam host AUR packages already use — and dedups
against that user's own `programs` so a tool declared in both installs once.
The selection→install decision is extracted as a pure function (host
post_install object + `users[0].programs` → deduped, order-preserving
program list) and unit-tested; the chroot wiring around it stays in the
Runner. Each tool's existing Program Install Script runs unchanged in the
per-user paru context.

**M5 — Terminal-action guard (pure).** When `post_install.security` or
`post_install.backup` resolves to a non-empty program list but the host has
no users, the terminal action (Proceed / Save / Export) aborts with an
actionable message ("security/backup install via paru and need a primary
user — add a user or clear the selections"). Consistent with validation
being deferred to the terminal actions.

**S1 — Two-level fzf loop (impure shell).** `lib/guided.sh` is
restructured: a top category loop renders categories (with `●` markers) +
the Proceed/Save/Export rows under a divider; Enter on a category opens a
sub-loop over that category's fields; `--expect=ctrl-z,ctrl-y,ctrl-r`
surfaces Undo/Redo/Reset in the header and the bash loop dispatches them
against the existing snapshot stack and reset verbs. New editors: the
firewall radiolist and the Security/Backup tool toggles. Esc returns to the
category list; edits commit on confirm, never on Esc (unchanged invariant).

**D1 — Data + migration.** Remove `firewalld`, `apparmor`, `clamav`,
`rkhunter` from `users/aquastias/profile.jsonc` (keep docker, virt-manager,
teamspeak3, podman, searxng). Migrate the two bool `post_install` profiles
(`hosts/vm/arch-secure`, `hosts/vm/arch-secure-kde-hyprland`) to the object
shape. The Environment Runner no longer dispatches a security/backup extra;
the dead `extras/security.sh` / `extras/backup.sh` references are removed.

## Testing Decisions

A good test asserts external behavior through a module's public interface —
state in, JSON/decision out — not its internals. The pure cores are
JSON-in / JSON-out and have no TTY, so they are bats-tested directly; the
fzf shell's only untestable part is the live draw, so it is exercised via
**stubbed fzf** (replay) plus the **guided VM smoke**, matching every prior
guided-installer issue.

bats coverage (all five pure modules):

- **M1** — `menu_categories` returns the eight categories in order with
  correct summaries and per-category `●` aggregation; `menu_category_rows`
  returns each category's fields; swap/esp surface under Disks while still
  pathing to `options.*`. Prior art: `tests/config/guided-menu.bats`.
- **M2** — the resolver maps every firewall choice + bool combination to
  the right program list; the secure-baseline default is firewalld + clamav
  + rkhunter + apparmor + zfs-auto-snapshot + borg; malformed objects are
  rejected. Prior art: `tests/config/guided-emit.bats`.
- **M3** — the seeded launch state carries hostname `eterniox`, `users[0] =
  aquastias`, single layout, locale/timezone/keymap, and the security/backup
  baseline. Prior art: `tests/config/guided-state.bats`.
- **M4** — host post_install ∪ `users[0].programs` dedups to a single
  order-preserving list; a tool in both appears once. Prior art:
  `tests/profiles/*` runner unit tests.
- **M5** — non-empty post_install + zero users → the guard errors; with a
  user, or with empty selections, it passes. Prior art:
  `tests/config/validation-*.bats`.

Smoke / VM (S1): stubbed-fzf render + loop-dispatch bats for the two-level
nav, `●` markers, keybind dispatch, and the Security/Backup editors (the
live fzf draw is the only smoke-only bit); a guided VM replay that drives
the Security/Backup categories through to a booting install asserts the
selected daemons are enabled. Prior art: `tests/config/guided-shell.bats`,
`tests/vm/profiles/single/guided*.jsonc`.

## Out of Scope

- Adopting a non-fzf TUI toolkit (dialog / whiptail / gum). Rejected — not
  guaranteed on the ISO; fzf stays.
- Making the security/backup tools host-installable for a **userless**
  server. They are paru-based User Programs; a userless install gets no
  firewall (pre-existing limitation, now surfaced as a fail-fast abort).
- Flipping the security/backup Programs to System Programs (`system:true`).
  Their install scripts assume paru + owning-user context (ADR 0041).
- Per-tool advanced configuration (firewall zones, clamav schedules) beyond
  install + enable — owned by each Program Install Script, not the menu.
- Multi-filesystem work (btrfs / ext4 / xfs / LUKS) — reserved per ADR 0040,
  untouched here.
- Live-system enumeration for locale/timezone/keymap pickers beyond the
  seeded defaults (the rows are editable; full live-list pickers can follow).

## Further Notes

- The redesign is rendering + fields + the Security/Backup landing model;
  the Config State, Emitter, History, Skeleton and Picker cores are reused.
  Keep the headless replay seam flat-keyed so the bats interface is stable.
- The `●` on a category row aggregates the existing per-field `overridden`
  flag — no new state, just a fold.
- Save strips device paths as today; the Security & Backup Extras objects
  are device-less host config and are written into the committed profile.
- Borg installs inert (it needs a post-boot repo init + passphrase); pre-
  ticking it is harmless and was an explicit operator choice.
