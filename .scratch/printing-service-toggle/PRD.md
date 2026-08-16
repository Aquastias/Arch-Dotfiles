# Printing service toggle (toggle-derived CUPS)

Status: ready-for-agent

Reference: ADR 0079 (`docs/adr/0079-printing-service-toggle-derived-system-program.md`),
CONTEXT.md glossary term **Printing Service (`options.printing.enabled`)**.

## Problem Statement

`cups` (the CUPS print daemon) is installed on **every** host unconditionally —
it is a hard-coded Host Core `system_programs` entry. An operator who does not
want a print server has no first-class way to say so: cups only appears buried as
an inherited row in the Guided Installer's Packages → system-programs picker,
where "turning it off" means writing a `system_programs_exclude` entry against a
program they never chose to add. The default is unclean: a printing daemon lands
on machines that will never print, and its provenance ("why is cups here?") is
invisible.

## Solution

Give printing its own first-class, discoverable switch. A new root-level
**Printing service** Configuration Category holds a single on/off toggle
(`options.printing.enabled`, default **on** to preserve today's behaviour). When
on, cups is installed in the chroot and `cups.service` enabled exactly as today;
when off, cups is genuinely absent — not installed at all. The toggle is cups's
**sole** home: it no longer clutters the Packages → system-programs picker, and
it surfaces in the read-only `derived` view / `explain-packages` as
`source=printing` so an operator can see precisely what the toggle pulls in.

## User Stories

1. As an operator building a headless/server host, I want to turn the printing
   service off, so that no CUPS daemon is installed on a machine that will never
   print.
2. As an operator who wants printing, I want it on by default, so that a fresh
   guided run behaves exactly as it does today with zero extra steps.
3. As an operator, I want a dedicated **Printing service** category in the menu,
   so that the print-daemon decision is discoverable and not buried among system
   programs.
4. As an operator, I want the toggle to flip in place on its category screen
   (Cycle Field), so that turning printing on/off is a single keystroke with no
   drill-in.
5. As an operator, I want the toggle to show an override dot only when I diverge
   from the default (on), so that the menu reflects exactly what I changed.
6. As an operator, I want cups to no longer appear in the Packages →
   system-programs picker, so that there is only one place to control printing
   and no confusing double representation.
7. As an operator, I want the `derived` section to list "Printing → cups (system
   program)" when the toggle is on, so that I can see the concrete package the
   switch installs.
8. As an operator using `explain-packages`, I want cups reported with
   `source=printing` and layer `derived`, so that the CLI answers "why is cups on
   this machine?" the same way it answers Security/Backup extras.
9. As an operator saving a Host Profile, I want an off-toggle persisted as
   `options.printing.enabled: false` (and on-toggle normalised out), so that a
   saved profile is a minimal delta over Host Core.
10. As an operator exporting an Effective Config, I want cups baked into
    `system_programs` only when printing is on, so that the exported artifact
    installs exactly what I selected.
11. As an operator on the `--profile` path, I want a committed profile's
    `options.printing.enabled` honoured at assembly time, so that printing state
    replays deterministically.
12. As an operator on the unattended `install.sh <config-file>` path, I want the
    pre-assembled config's `system_programs` to already carry (or omit) cups per
    the authoring front-end's toggle, so that unattended installs match guided
    ones.
13. As an operator, I want cups installed as a root/chroot System Program exactly
    as before (its Program dir and `install.sh` unchanged), so that the print
    daemon and its `cups.service` come up on first boot independent of desktop
    environment.
14. As a maintainer, I want `cups` removed from Host Core `system_programs`, so
    that the "installed on every host" default is expressed by the toggle's
    default, not a hard-coded core entry.
15. As a maintainer, I want `options.printing.enabled` accepted by the closed
    profile schema, so that authoring it does not abort at load and typos in
    neighbouring keys still do.
16. As a maintainer, I want a single pure function to be the source of truth for
    "does printing put cups on the machine?", so that the Effective-Config
    assembly and the Package Resolver can never drift.
17. As an operator, I want printing to remain independent of desktop-environment
    selection, so that a server with no DE can still enable a print server and a
    desktop can still disable one.

## Implementation Decisions

- **New schema field `options.printing.enabled`** — a boolean, default `true`,
  normalised out of Config State when equal to the default (so only opting *out*
  writes a `●` override). Modelled on `options.ssh.enabled`. Added to the closed
  profile schema allowlist and to the config accessors in lockstep (an accessor
  like `printing_enabled`, default `true`), and to the guided seed defaults so
  the menu baseline carries it.

- **New Configuration Category "Printing service"** — a root-level category
  (peer of Security/Backup, not folded into General) holding exactly one field
  row bound to `options.printing.enabled`. Because its option set is exactly
  `{true,false}`, it is structurally a **Cycle Field** (flips in place, no
  drill-in) via the existing `{true,false}`-detection — no new field kind. Added
  to the menu category table and field table with a one-line summary. Placement
  in canonical reading order is an author call (recommended near
  Environment/Security); the category count in CONTEXT.md rises accordingly.

- **`cups` removed from Host Core** — the `system_programs: ["cups"]` entry is
  deleted from `.os/hosts/core/profile.jsonc`. cups keeps its Program directory,
  `config.jsonc` (`system: true`), and `install.sh` (installs cups + enables
  `cups.service`) unchanged.

- **Single pure toggle→program function (source of truth)** — a new pure module
  function (mirroring `post_install_programs`) that, given a config object,
  emits the toggle-derived System Programs: `cups` when
  `options.printing.enabled` is true, nothing when false. Both consumers below
  call it; the mapping lives in exactly one place.

- **Effective-Config injection** — at Effective-Config assembly
  (`assemble_profile_config` and the guided emit path), the assembled
  `system_programs` gains cups when the pure function says so. This is the only
  place cups enters the installed set; the Runner then installs it in the chroot
  exactly as an authored System Program. The unattended
  `install.sh <config-file>` path consumes a pre-assembled config and is
  unaffected (its `system_programs` already reflects the authoring front-end's
  toggle).

- **Package Resolver reporting** — the resolver (today reporting *no* system
  programs at all) gains one derived entry: it calls the same pure function and,
  when cups is produced, emits it as `source=printing`, layer `derived`. This
  flows to the guided read-only `derived` section and `explain-packages`,
  matching the Security/Backup provenance shape.

- **Picker filter** — cups is filtered out of the Guided Installer's Packages →
  system-programs picker (the program is toggle-owned), so the Printing category
  is its sole menu home and no double representation survives. The filter is
  scoped to the toggle-owned program(s); other system programs (grub, sops) are
  untouched.

- **No install-state / chroot-service change** — unlike `options.ssh.enabled`
  (which threads `SSH_ENABLED` to a chroot `base-services` enable), printing
  needs no install-state key: cups is installed via the existing
  `system_programs` → Runner path, and its service is enabled by its own
  `install.sh`. The toggle's only job is deciding cups's *presence* in
  `system_programs`.

- **CONTEXT.md** — already updated with the **Printing Service** glossary term
  and the corrected category list (`General`, `Pacman`); the category count moves
  from thirteen to fourteen when this lands.

## Testing Decisions

Good tests here assert **external behaviour** — "given this config, is cups on
the machine / in the report / in the menu?" — never the internal shape of the
injection. Five seams, one primary:

1. **Primary seam — the pure toggle→program function** (new
   `tests/config/printing.bats`, mirroring `tests/config/post-install.bats`):
   feed a config with `options.printing.enabled` true → output contains `cups`;
   false or absent-with-default-off → output is empty; default (unset) → treated
   as on. Pure, headless, no VM.

2. **Effective-Config assembly** (extend `tests/config/configs.bats` and the
   guided emit test `tests/config/guided-emit.bats`): the assembled/emitted
   `system_programs` contains `cups` iff printing is on. Prior art: existing
   assembly assertions in those files.

3. **Package Resolver** (extend `tests/explain-packages.bats`): with printing on,
   cups appears with `source=printing` / layer `derived`; with printing off, cups
   appears nowhere in the report. Prior art: the Security/Backup derived
   assertions already in that file.

4. **Guided menu + picker** (extend `tests/config/guided-menu.bats` and
   `tests/config/guided-packages.bats`): the **Printing service** category and
   its Cycle Field render with the correct default and override-dot behaviour;
   `cups` is absent from the system-programs picker list. Prior art: existing
   category/field and picker-list assertions in those files.

5. **Schema + seed** (extend `tests/config/profile-loader.bats` and
   `tests/config/guided-seed.bats`): a profile carrying
   `options.printing.enabled` loads without aborting, an unknown neighbour key
   still aborts with its path, and the seed baseline defaults printing on.

The combination matrix registry may gain `options.printing.enabled` as a
pairwise-affecting light axis (mirroring the `options.ssh.enabled` row) if cheap;
otherwise it is out of scope (see below).

## Out of Scope

- Multiple printing backends or driver/package choices (e.g. `cups-pdf`, SANE,
  Avahi/mDNS discovery). The toggle is a single bool over the existing cups
  Program; a richer enum is a future ADR.
- Enabling/disabling `cups.service` independently of installing the package. The
  toggle gates *installation*; service-enable stays inside cups's `install.sh`.
- Any change to how other System Programs (grub, sops) are declared or installed.
- Retrofitting the resolver to report *all* system programs — only the
  toggle-derived cups entry is added.
- A VM smoke-test cell specifically for printing, unless the matrix axis is added
  cheaply; the pure + bats seams cover the behaviour headlessly.

## Further Notes

- The one genuinely new mechanism is a **toggle-derived System Program**: nothing
  else in the codebase derives a *system* program from a bool
  (`options.ssh.enabled` only toggles a service on an always-present package).
  Reviewers should expect the pure-function + assembly-injection shape rather
  than an install-state thread — this is deliberate and recorded in ADR 0079.
- Keeping cups a real System Program (not inlining it like sshd) preserves the
  Program Registry / Program Runner path and the `system: true` invariant, so the
  only thing that changed is *what puts cups on the list*.
