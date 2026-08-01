# PRD: Layered software model — simplify what lands on the system

Status: `ready-for-agent`

Data annex: [CURATION.md](./CURATION.md) — the per-package layer assignments
(141 entries) and the 22 numbered findings (R1–R22) this PRD acts on.

## Problem Statement

I maintain two machines (`desktop`, `laptop`) plus three VM test fixtures, and
I cannot tell what software will actually be on a machine after an install.

There are **18 distinct paths** by which a package reaches the system, and I
author **7** of them. Two of those seven are pure redundancy —
`packages.groups` is used by no profile at all, and `packages.extra` is
`packages.repo` without a category. When I want to add a program I have to
decide between five slots with no rule telling me which is right.

The layering doesn't help either, because there effectively isn't any. Host
Core declares one System Program and a swappiness value; everything else is
duplicated between the two host profiles. `laptop` is a strict subset of
`desktop` — 57 repo packages in both, zero unique to laptop — yet both files
carry the full list.

The installer's menu actively misleads me:

- Host Core's contents appear nowhere. `cups` installs on every host and is
  invisible in the menu, because `cfgstate_seed_defaults` hand-copies a few
  Host Core values rather than loading Host Core.
- The menu merges arrays by replacement while the installer merges by
  concatenation, so seeding from `desktop` shows `system programs: grub` while
  the install produces `["cups", "grub"]`.
- `packages.repo` and `packages.aur` have no menu representation at all.
  Seeding a profile silently carries 139 packages into Config State that I can
  neither see nor deselect.
- Both program pickers offer every program regardless of its `system` flag, so
  most of what they offer produces a config that fails validation.

And the same config file installs differently depending on which front-end
reads it: the rule that promotes a `packages.extra` entry naming a Program into
`system_programs` runs only in the Guided Installer's emit path. `install.sh
--profile` and `install.sh <config-file>` never promote. Configurations must
behave identically whether I hand-edit them or author them in the TUI.

## Solution

**Five authored slots, one routing rule, and one command that answers "what
lands?".**

Delete the two redundant slots. `packages.groups` goes entirely; the internal
GPU/audio buckets that share its namespace are renamed so they are visibly
derived, not authorable. `packages.extra` goes; the Guided Installer's "extra
packages" row writes into a `packages.repo` category instead.

What remains is mechanical:

```
Does the name resolve to a Program directory?
  yes → system: true   → host system_programs
        system: false  → user programs
  no  → official repos → packages.repo
        AUR            → packages.aur
```

Everything else — base packages, kernel, bootloader, GPU drivers, audio,
filesystem tools, login shell, the Plasma shell, KDE applications, and
secrets-activated sops — is **derived** from a setting I already made, and is
never declared.

Make Host Core a real base. It gains a `packages` object, so it holds the 61
packages both machines share and each host profile becomes a delta. `laptop`
ends up with no packages block at all. The VM fixtures opt out with
`packages.inherit: false`.

Unify the merge rule. One per-key classification — additive sets versus
ordered selections — used by both the installer and the menu, so they can
never again disagree about what is installed.

Delete the promotion rule. Program-and-package overlap becomes a config-load
abort, so every front-end reads the same file the same way, and the Guided
Installer routes what I type before storing it rather than rewriting it later.

Finally, make the resolved set inspectable. A single resolver, shared by a CLI
inspector and the menu's read-only `derived` section, prints every package with
its provenance — working identically on a hand-edited profile and a TUI-authored
one.

## User Stories

1. As an operator, I want one rule that tells me which slot a new program goes
   in, so that I do not have to guess between five lists.
2. As an operator, I want `packages.groups` removed, so that a slot no profile
   uses stops appearing in the schema.
3. As an operator, I want `packages.extra` folded into `packages.repo`, so that
   there is exactly one place for repo packages.
4. As an operator, I want the GPU and audio buckets renamed out of the
   `packages` namespace, so that derived sets are not mistaken for things I can
   author.
5. As an operator, I want Host Core to carry a `packages` object, so that
   software shared by every host is declared once.
6. As an operator, I want a host profile to be a delta over Host Core, so that
   adding a machine means listing only what is different about it.
7. As an operator, I want `hosts/laptop` to carry no packages block, so that
   the subset relationship between my machines is visible in the files.
8. As an operator, I want an `exclude` key on a host profile, so that a machine
   can drop something Host Core declares.
9. As an operator, I want exclusions to fold in layer order with the last layer
   winning, so that a leaf profile always has the final say about its own
   machine.
10. As an operator, I want `packages.inherit: false` on the VM fixtures, so
    that test installs stay lean without maintaining an exclude list that grows
    every time Host Core does.
11. As an operator, I want `users/core` to carry a real `programs` list, so
    that a new user inherits my standard tooling.
12. As an operator, I want `programs_exclude` on a user profile, so that
    throwaway test users do not build programs they will never run.
13. As an operator, I want one merge rule shared by the installer and the menu,
    so that the menu cannot show me a different set from what installs.
14. As an operator, I want additive keys to concatenate and ordered selections
    to replace, so that Host Core can contribute packages without a host being
    unable to switch kernels.
15. As an operator, I want a package name that resolves to a Program to abort
    at config load, naming the path and the correct slot, so that the mistake
    is caught before any disk is touched.
16. As an operator, I want the promotion rule deleted, so that a hand-edited
    config installs exactly what a TUI-authored one does.
17. As an operator, I want the Guided Installer to route a Program name I type
    into the extra-packages box at entry time, so that I get the convenience
    without the stored config becoming non-canonical.
18. As an operator, I want the menu's baseline loaded from Host Core rather
    than hand-copied, so that everything Host Core installs is visible in the
    menu.
19. As an operator, I want `cups` to appear as a selected System Program, so
    that I can see the thing that installs on every one of my hosts.
20. As an operator, I want a Packages screen that drills by category, so that I
    can browse the package set the same way the JSONC is organised.
21. As an operator, I want inherited packages shown checked without an override
    dot, so that I can tell at a glance what came from Host Core.
22. As an operator, I want packages added by this profile or session marked
    with a dot, so that I can see my own edits.
23. As an operator, I want unchecking an inherited package to write an
    `exclude` entry, so that the exclusion mechanism is reachable from the menu.
24. As an operator, I want a read-only `derived` section listing what my
    Environment, Security and Backup choices pull in, so that the menu stops
    under-reporting the install.
25. As an operator, I want the host System Programs picker to offer only
    `system: true` programs, so that I cannot build a config that fails
    validation at Proceed.
26. As an operator, I want the User Editor's programs picker to offer only
    `system: false` programs, so that picking one is never a silent no-op.
27. As an operator, I want a CLI command that prints the resolved package set
    with provenance, so that I can answer "what lands?" without launching the
    installer.
28. As an operator, I want that command to work on a hand-edited profile, so
    that the TUI is a convenience and not a requirement.
29. As an operator, I want the inspector and the menu's derived section to
    share one resolver, so that they cannot drift.
30. As an operator, I want the inspector to show which layer each package came
    from, so that I can tell whether to edit Host Core or a host profile.
31. As an operator, I want the inspector to list excluded packages separately,
    so that I can confirm an exclusion took effect.
32. As an operator, I want Save Profile to write a delta over Host Core, so
    that a saved profile stays layered rather than freezing a snapshot.
33. As an operator, I want the KDE adapter's applications section to install
    only KDE applications, so that the installer's output matches what it says
    it is doing.
34. As an operator, I want DE-tied packages that are not applications to
    install with the Plasma shell, so that `apps_list` stays a list of
    applications.
35. As an operator, I want non-KDE tools removed from the KDE adapter, so that
    selecting KDE does not install a third-party pacman frontend.
36. As an operator, I want `stow` in the Base Package List, so that the
    dotfiles step cannot fail on a host that did not happen to declare it.
37. As an operator, I want filesystem tools, the login shell, and the audio
    stack derived rather than declared, so that I cannot forget one when
    changing a setting.
38. As an operator, I want `save-pkglist.sh` to take a profile name, so that it
    works again after ADR 0020 decoupled profile names from hostnames.
39. As an operator, I want `save-pkglist.sh` output labelled a drift snapshot,
    so that I do not replay it into a profile and collapse the layering.
40. As an operator, I want packages that arrive as dependencies of something
    already installed dropped from my lists, so that my profiles state
    intentions rather than restate the dependency graph.
41. As a maintainer, I want the Layer Resolver to be a pure function, so that
    the layering contract is testable without a VM.
42. As a maintainer, I want the Package Resolver to be a pure function, so that
    provenance is testable without a VM.
43. As a maintainer, I want the program registry to carry the `system` flag, so
    that a menu render does not re-parse fifteen JSONC files.
44. As a maintainer, I want the real profiles resolved and asserted in bats, so
    that a curation mistake fails in seconds rather than in a VM install.

## Implementation Decisions

### Modules

Four deep modules carry the logic. Everything else is thin glue over them.

**Layer Resolver.** Takes Host Core and a host profile (or User Core and a user
profile) and returns the effective set. Owns three things: the additive/replace
key classification, the `exclude` fold, and `inherit: false`. Pure — JSON in,
JSON out, no filesystem, no TTY. Replaces the two divergent merge rules in use
today, one in the config-load path and one in the guided effective view.

The classification principle is **unordered set versus ordered selection**:

- *Additive* — concat, dedupe, `exclude` subtracts: `packages.repo.*`,
  `packages.aur.*`, `system_programs`, `users`, `persist.directories`,
  `persist.files`, `sysctl` (deep merge), and on the user side `groups`,
  `programs`, `ssh_authorized_keys`.
- *Replace* — a later layer wins outright: `options.kernel` (element 0 is the
  Primary Kernel), `system.locale`, `system.keymap` (element 0 is the default),
  `environment.desktop`, `environment.gpu`, `options.mirror_countries` (ordered
  preference), `storage_groups[]`, `data_pools[]` (positional), and every
  scalar.

Layers fold in order and the last layer wins, so a host may re-add something a
lower layer excluded.

**Package Resolver.** Takes an Effective Config and returns every package that
will be installed, each tagged with its source and layer. Covers the authored
slots, the Base Package List, and all derived sets — kernel, bootloader, GPU,
audio, filesystem tools, login shell, Plasma shell, KDE applications, KDE AUR,
Security & Backup Extras, and secrets-activated sops. Pure: every input is
declarative, so it needs no pacman query. Consumed by the CLI inspector, the
menu's `derived` section, and the real-profile regression tests.

**Program Registry.** Extends the existing name → `category/name` index with
the `system` flag, exposing a single `program kind` lookup returning `system`,
`user`, or `none`. Built once. Backs the exclusivity validator, both guided
pickers, and the resolver.

**Exclusivity Validator.** Given the registry, aborts config load when any
`packages.repo` or `packages.aur` entry resolves to a Program directory, naming
the offending path and the correct slot. This replaces the promotion rule.

### Schema changes

- Host Core gains `packages` (`repo` + `aur`, both Categorized Lists). Amends
  ADR 0007, whose "the lists are machine-specific" premise no longer holds.
- New `packages.exclude[]` and `system_programs_exclude[]` on a host profile;
  `programs_exclude[]` on a user profile.
- New `packages.inherit` (bool, default true) — scoped to packages only, so a
  fixture still inherits Host Core's users and sysctl.
- Removed: `packages.extra[]`, `packages.groups.*[]`.
- The internal GPU and audio buckets move out of the `packages` namespace into
  a clearly-derived one, and are rejected if authored.
- All new keys register with the closed schema, which aborts on unknown keys at
  any depth (ADR 0036).

### Layering

Two layers, Host Core → host profile. No `hosts/base/` tier, no `extends`. A
three-tier model was designed and rejected: it existed solely to keep the VM
fixtures lean, and `packages.inherit: false` buys the same outcome for one key
instead of a permanent concept. `hosts/laptop` losing its packages block
entirely is the confirmation that two layers fit this fleet.

`users/core` gains a real `programs` list; there is no `users/base/` tier.

### Guided Installer

- The menu baseline loads `hosts/core/profile.jsonc` instead of hand-copying a
  handful of its values, so Host Core's contents surface as seeded-but-unmarked
  rows.
- The menu's effective view uses the Layer Resolver, so display and install
  agree.
- Packages category drills `repo` → category → package toggles, mirroring the
  Categorized List shape. Three states: checked-without-dot means inherited,
  checked-with-dot means added here, unchecked-with-dot means excluded.
  Unchecking an inherited entry writes an `exclude` entry.
- A read-only `derived` section lists what the current Environment, Security
  and Backup choices pull in, grouped by source. Not toggleable — ADR 0021
  keeps the DE adapter owning its own package set.
- The two program pickers filter on the `system` flag via the registry.
- Save Profile writes a plain delta over Host Core.
- The package toggle list can only offer the declared union across Host Core
  and the profile; adding a brand-new package remains a free-text entry, since
  the universe of Arch packages is not enumerable.

### KDE adapter

`apps_list` holds only applications. The mechanical rule: a package belongs
there iff its pacman `Groups` contains `kde-applications`; `plasma` and `kf5`
groups belong to the shell section; anything else is not KDE and belongs in a
host profile. Verified against <https://apps.kde.org/>. Details and the
per-package evidence are in CURATION.md R21.

The DE-tied packages relocated *into* the adapter from host profiles (ADR 0021,
CURATION.md R10) also go to the shell section — they are DE-tied but they are
not applications.

### Tooling

- A CLI inspector prints the resolved set with provenance, calling the Package
  Resolver. Takes a profile name; works on any committed profile without
  launching the installer.
- `save-pkglist.sh` takes a **profile** name rather than `$(hostname)`, fixing
  a breakage introduced when ADR 0020 decoupled the two, and stamps its output
  as a drift snapshot that must not be replayed into a profile.
- `stow` joins the Base Package List — the Runner invokes it unconditionally
  for every user but no layer guaranteed it.
- The derived audio set gains the three PipeWire-adjacent packages currently
  declared by hand.

### ADRs

- **0056** — Host Core carries packages; fixtures opt out via
  `packages.inherit`. Amends ADR 0007.
- **0057** — Per-key merge classification: additive sets versus ordered
  selections, shared by installer and menu.
- **0058** — Guided package surface: Host Core as menu baseline, provenance
  marks, read-only derived section, and the deletion of front-end-specific
  promotion.

## Testing Decisions

A good test here asserts **external behaviour**: given these profile files,
this is the resolved set. It does not assert how the merge is implemented, nor
reach into intermediate state. The four deep modules are pure JSON-in/JSON-out
functions precisely so this is possible without a VM.

Prior art: `tests/config/guided-edits.bats` and `tests/config/guided-promote.bats`
are the closest existing shape — pure functions exercised with literal JSON
fixtures and asserted with `jq`. `tests/config/configs.bats` is the prior art
for asserting against the real committed profiles.

**Layer Resolver.** Additive keys concatenate and dedupe; replace keys are
overwritten wholesale; `exclude` removes an inherited entry; a later layer
re-adds something an earlier layer excluded; `inherit: false` yields no
inherited packages while still inheriting users and sysctl; every key in the
classification table is covered by at least one case.

**Package Resolver.** Every source appears with correct provenance; a derived
set changes when its driving setting changes (GPU vendor, desktop selection,
filesystem, login shell, bootloader); excluded packages are reported separately
and are absent from the installed set; the resolver is deterministic for a
given config.

**Program Registry.** `system`, `user` and `none` all resolve correctly; an
unknown name returns `none`; the registry is built once and reused.

**Exclusivity Validator.** A `packages.repo` entry naming a system Program
aborts; one naming a user Program aborts; the message names the path and the
correct slot; a plain package passes; an empty package list passes.

**Real-profile regression.** Resolve the committed `core`, `desktop` and
`laptop` profiles end-to-end and assert the final package sets, so a curation
mistake fails in bats rather than in a VM install. This also pins the
invariants the curation established — `laptop` contributing no packages, no
Program name appearing in any package list, and no package appearing that a
derived set already provides.

**Menu option-set membership** was considered and is deliberately deferred (see
Out of Scope).

## Out of Scope

- **Menu option-set membership tests.** The gap that let the two bad pickers
  through is that existing tests assert `[x]`/`[ ]` marking but never which
  options are offered. Worth fixing, but it is a guided-surface testing concern
  rather than part of this model change.
- **Adding `packages.inherit` / `exclude` as a Combination Matrix axis.** The
  fixtures' opt-out will be covered by unit tests; wiring it into Tier 1 is
  separate work.
- **Dotfiles theming.** The catppuccin purge is packages-only. The 22 tracked
  theme files and their references in 9 configs are untouched; the GTK, SDDM,
  Plasma, Konsole, cursor and papirus-folders surfaces will fall back to stock
  because their themes came from the purged packages. Cleaning up or repointing
  those references is separate work.
- **Plymouth.** Adding a boot splash properly — mkinitcpio hook, `quiet splash`
  cmdline, interaction with the encryption passphrase prompt and the
  Impermanence Rollback Hook — is its own change. The orphaned theme package is
  simply removed.
- **zram.** ADR 0045 rejected it in favour of zswap. The unconfigured
  `zram-generator` package is removed; adding real zram support would need a
  schema block, a config writer, and an ADR superseding 0045.
- **Per-host user program deltas.** `users/<name>/profile.jsonc` is
  host-independent by design, so "this program for this user on this host only"
  is not expressible. It did not block anything here, but it is a real gap.
- **A `hosts/base/` tier and `extends`.** Designed, then rejected in favour of
  two layers. Revisit only if a real headless or server host appears.

## Further Notes

The curation is complete and recorded in CURATION.md: 141 packages assigned
across `core` 61, `desk` 34, `derive` 6, `drop` 39, and one addition to the
Base Package List. The `derive` bucket turned out more interesting than `core`
— six packages were being declared by hand while the installer already computed
them, meaning they were not misplaced across layers so much as they should
never have been declared at all.

Several findings are live bugs independent of this refactor and are fixed
incidentally: `teamspeak3` declared as a repo package when it is AUR-only,
`stow` required but unguaranteed, `kimageformats5` installing a stale KF5
parallel stack, `xdg-desktop-portal-kde` already supplied by `plasma-meta`,
`zram-generator` installed but never configured, and `save-pkglist.sh` broken
since ADR 0020.

Two decisions were reversed during design and the reasoning is worth keeping.
The three-tier `core → workstation → host` model was fully specified before
being collapsed — it optimised for a hypothetical headless host at the cost of
a concept in daily use. And `grub` in `desktop`'s `system_programs` looked like
a contradiction against `bootloader: systemd-boot` but is deliberate: a rescue
GRUB with os-prober, documented in the Program's own config and asserted by an
existing test.

The shell default changes from `/bin/bash` to `/bin/zsh`. The entire tracked
shell payload is zsh — 18 files under `.zsh/` plus five dotfiles — while
`.bashrc`, `.bash_profile` and `.profile` are untracked, so today a fresh
install lands in bash with a stowed zsh config that never loads. Neither `zsh`
nor `zinit` needs declaring: the chroot installs a user's login shell package
automatically, and the zinit config git-clones itself on first interactive
shell. That clone needs network at first login.
