# PRD: DE Adapter Package Ownership and Categorized List Schema

Status: done
Category: enhancement

## Problem Statement

Today the desktop Host Config (`hosts/desktop/config.jsonc`) duplicates
packages already installed by the KDE Desktop Environment Adapter
(`kde.sh`). The shell stack (`plasma-meta`, `plasma-workspace`,
`polkit-kde-agent`, `kimageformats5`, `extra-cmake-modules`, etc.) is
hardcoded inside `kde.sh`'s `do_shell` branch *and* listed again under
`packages.repo` in the host config. KDE applications (`ark`, `dolphin`,
`kate`, …) are declared both in `install-kde.jsonc:apps_list` and in
the host's `packages.repo` — two sources of truth that drift.

Worse, the KDE adapter installs packages that aren't KDE
(`extra-cmake-modules` is a build-time dep; `cups` is the Linux print
daemon, not Plasma), leaking opinions into a shell that should encode
only "what Plasma needs to boot". Operator can't tell from
`install-kde.jsonc` what the adapter will actually install — half the
list lives in shell-script literals.

Separately, `packages.repo` and `packages.aur` in Host Configs are flat
string arrays. Operators want to group packages by purpose (`browsers`,
`dev`, `media`) for readability, but the parser only accepts a flat
list. The same problem repeats in `install-kde.jsonc:apps_list`:
twenty KDE apps in one alphabetical bucket, no way to organise them
cosmetically.

Finally, when running KDE + Hyprland together, `qt6ct-kde` is needed so
Qt apps launched under Hyprland inherit a coherent theme — but it's
AUR, and Desktop Environment Adapters are pacman-only today, so there
is no clean home for it.

## Solution

Two coupled changes:

**1. Desktop Environment Adapter owns all DE packages.** Host Configs
declare no KDE packages by default. The KDE adapter holds:
- a minimal hardcoded Plasma stack in `kde.sh` (`plasma-meta`,
  `plasma-workspace`, `polkit-kde-agent`, `sddm`, `print-manager`) —
  non-negotiable for a working session,
- everything else (apps, Qt plugins, portal integrations) in
  `install-kde.jsonc:apps_list` as togglable defaults.

Hyprland adapter gains a new `aur:` field with the same shape as
`apps_list`. The Runner reads adapter `aur:` lists alongside the host
AUR list and installs both in one paru pass. `qt6ct-kde` lives in
`install-hyprland.jsonc:aur` under a `qt_theming` category, defaulting
on — installed only when Hyprland is selected.

Two packages currently mis-located in `kde.sh` move out:
`extra-cmake-modules` → Host Core `packages.repo` (pure pacman
dependency, no service); `cups` → new System Program at
`.os/programs/<cat>/cups/` so service enablement is owned by its own
install script.

**2. Categorized package list schema.** Every list-of-strings or
list-of-booleans field used to declare packages becomes a 2-level
object `{ category: [items] }` (or `{ category: { pkg: bool } }` for
toggles). Categories are kebab-case, validated. The parser flattens to
a sorted, deduped, opaque list — categorization is purely cosmetic at
install time. Fail-fast on shape or leaf-type violations.

The result: a single declarative source of truth per concern
(Plasma packages in the KDE adapter; user host preferences in the host
config), uniform schema across four sites, and a documented seam for
adapters that need AUR packages.

## User Stories

1. As an operator, I want the KDE adapter to own every KDE package,
   so that I never have to keep two lists in sync between
   `install-kde.jsonc` and the host config.
2. As an operator, I want a host config to declare zero KDE
   applications by default, so that selecting `environment.desktop=kde`
   pulls in the full canonical KDE app set automatically.
3. As an operator, I want to remove an unwanted KDE app by flipping a
   boolean in `install-kde.jsonc`, so that I can de-select individual
   apps without rewriting `kde.sh`.
4. As an operator, I want `kde.sh` to install only Plasma-required
   packages in its shell phase, so that opinions like CUPS and ECM
   don't leak into "what Plasma needs to boot".
5. As an operator, I want `cups` to be a System Program with its own
   `install.sh`, so that the printing service is enabled where service
   enablement actually lives — not as a side effect of selecting KDE.
6. As an operator running KDE + Hyprland, I want `qt6ct-kde` installed
   automatically, so that Qt apps launched under Hyprland inherit a
   coherent theme without manual intervention.
7. As an operator running only KDE, I want `qt6ct-kde` *not* to be
   installed, so that I don't get a Qt config tool that does nothing
   useful inside Plasma.
8. As an operator, I want adapters to declare their AUR packages in
   their own `install-<de>.jsonc:aur` field, so that adapter-specific
   AUR needs don't pollute the host config.
9. As an operator, I want adapter AUR installs to happen in the
   same paru pass as host AUR installs, so that I don't pay the
   bootstrap cost twice and ordering is predictable.
10. As an operator, I want `packages.repo` in my host config to be a
    categorized object, so that I can group packages by purpose
    (`browsers`, `dev`, `media`) for readability.
11. As an operator, I want `packages.aur` in my host config to use the
    same categorized shape as `packages.repo`, so that I don't have
    to remember two schemas.
12. As an operator, I want `install-kde.jsonc:apps_list` to be
    categorized, so that twenty KDE apps stop reading as one
    alphabetical wall of text.
13. As an operator, I want categories to be purely cosmetic, so that
    renaming `media` to `multimedia` doesn't change what gets
    installed.
14. As an operator, I want categories to enforce kebab-case, so that
    drift between `media`, `Media`, `media-apps`, and `mediaapps`
    is rejected by the parser.
15. As an operator, I want any malformed list (wrong leaf type, wrong
    depth, invalid category name) to fail the install before pacstrap,
    so that I catch typos at config-load time, not in the middle of an
    install.
16. As an operator, I want duplicate packages across categories to be
    silently deduped, so that `firefox` in both `browsers` and
    `web` doesn't double-install or warn.
17. As an operator, I want the strict 2-level shape applied
    everywhere, so that single-package fields still take the form
    `{misc: ["parallel"]}` and the schema stays uniform.
18. As an operator, I want the `extra: []` field removed from
    `install-kde.jsonc`, so that there's exactly one way to add a KDE
    package — `apps_list` under a category.
19. As an operator, I want the `shell: true` / `apps: true` flags in
    `install-kde.jsonc` preserved, so that I can still toggle the
    entire shell phase or apps phase atomically.
20. As an operator, I want the Plasma minimal core to remain
    hardcoded in `kde.sh`, so that I can't accidentally produce an
    un-bootable Plasma install by toggling `plasma-meta` off.
21. As an operator, I want `pacmanlogviewer` and `octopi` migrated to
    `install-kde.jsonc`, so that the host config holds nothing that
    can be derived from the desktop environment selection.
22. As a future maintainer, I want a single Categorized List Parser
    reused at all four sites (host repo, host AUR, adapter apps_list,
    adapter aur), so that the validation rule lives in one place and
    behaviour is identical everywhere.
23. As a future maintainer, I want the parser to be a pure function
    over JSON, so that it can be unit-tested in isolation without
    spinning up a VM or touching the filesystem.
24. As a future maintainer, I want the Runner's adapter-AUR discovery
    to read `extras/desktop/<de>/install-<de>.jsonc` directly, so that
    the data lives next to the adapter and the Runner doesn't depend
    on intermediate state files.
25. As a future maintainer, I want two ADRs covering the two
    independent decisions (adapter ownership; categorized schema), so
    that either can be revisited without re-litigating the other.
26. As a future maintainer, I want `CONTEXT.md` updated alongside the
    implementation PR, so that the glossary never describes a schema
    that doesn't yet exist nor lags one that does.

## Implementation Decisions

### Modules

**Categorized List Parser** (new, deep, pure)
- Input: a JSON value parsed from JSONC, plus a leaf-type tag
  (`"string"` for package lists, `"bool"` for toggle maps).
- Validation rules: object at top level; keys match
  `^[a-z0-9-]+$`; values are arrays (for string leaves) or objects
  (for bool leaves); leaves are the declared type; depth is exactly
  two; empty categories permitted; duplicate leaves across categories
  permitted.
- Output: deterministically-ordered, deduped flat list.
  - String mode: `sorted_unique(strings)`.
  - Bool mode: only entries with `true` are emitted; output is
    `sorted_unique(keys_where_value_is_true)`.
- Failure mode: abort via `error` with a precise message naming the
  offending key/path. No partial parse.
- No I/O. No state. Used by the KDE adapter, the Hyprland adapter,
  the pacstrap list builder, and the Runner's AUR pass.

**KDE Desktop Environment Adapter (`kde.sh`)** (modified)
- Shell phase installs a hardcoded minimum: `plasma-meta`,
  `plasma-workspace`, `polkit-kde-agent`, `sddm`, `print-manager`.
- `cups`, `extra-cmake-modules` removed from this script.
- App phase consumes `install-kde.jsonc:apps_list` via the new parser
  (was: flat `jq to_entries` traversal).
- `extra: []` field removed from both the script and the JSONC.
- A `plasma_extras` category in `apps_list` carries previously-shell
  packages now exposed as toggles: `sddm-kcm`, `kimageformats5`,
  `xdg-desktop-portal-kde`.
- All current KDE applications stay defaulted to `true` so the
  default install matches today's behaviour. New entries:
  `pacmanlogviewer`, `octopi` (the latter declared in
  `install-kde.jsonc:aur` once the field is added for parity, since
  `octopi` is AUR).

**Hyprland Desktop Environment Adapter (`hyprland.sh` /
`install-hyprland.jsonc`)** (modified)
- New `aur:` field with the same 2-level boolean-toggle schema as
  `apps_list`. Adapter does *not* install AUR itself; declaration only.
- `qt_theming.qt6ct-kde: true` ships as the only default entry.
- Adapter's repo install path keeps using the parser for its
  togglable companion tools (consistency, future-proofing).

**Runner AUR discovery (`lib/profiles.sh`)** (modified)
- Before invoking paru as the primary user, iterate
  `environment.desktop[]` (resolved at config-load time), read
  `extras/desktop/<de>/install-<de>.jsonc:aur` for each, parse
  through the Categorized List Parser, union with the host's
  `packages.aur` (also parsed). Single deduped list fed to paru.
- If an adapter file has no `aur:` field, contribute nothing
  (no warning — absence is normal).

**Pacstrap list builder (`lib/packages.sh`)** (modified)
- The current `jq -r '.packages.repo[]?'` replaced by a call to the
  Categorized List Parser over `host_json.packages.repo`.
- Same change for any other read site that touches `packages.repo`
  or `packages.aur`.

**Host Configs** (modified)
- `hosts/core/config.jsonc`: `packages.repo` reshaped from
  `["parallel"]` to `{ "misc": ["parallel", "extra-cmake-modules"] }`
  (or chosen category name). `system_programs` stays flat (`["sops",
  "cups"]` after the new program lands).
- `hosts/desktop/config.jsonc`: all KDE packages stripped (apps,
  Plasma stack, Qt plugins). Remaining packages reshaped into
  categories chosen by the operator (cosmetic; suggested:
  `browsers`, `dev`, `media`, `gaming`, `system`, `qt-extras`).

**`cups` System Program** (new)
- New tree at `.os/programs/<category>/cups/` with `config.jsonc`
  (`"system": true`) and `install.sh` that runs `pacman -S --needed
  cups` and `systemctl enable cups.service`.
- Listed in `hosts/core/config.jsonc:system_programs`.
- Category placement to match repo's existing program taxonomy.

### Schema (canonical examples)

Host `packages.repo`:
```jsonc
{
  "packages": {
    "repo": {
      "browsers": ["firefox"],
      "dev": ["git", "go", "neovim"]
    },
    "aur": {
      "browsers": ["brave-bin", "zen-browser-bin"]
    }
  }
}
```

`install-kde.jsonc`:
```jsonc
{
  "shell": true,
  "apps": true,
  "apps_list": {
    "plasma_extras": {
      "sddm-kcm": true,
      "kimageformats5": true,
      "xdg-desktop-portal-kde": true
    },
    "file_management": {
      "dolphin": true,
      "krusader": true
    }
  },
  "aur": {
    "system": { "octopi": true }
  }
}
```

`install-hyprland.jsonc`:
```jsonc
{
  "bar": true,
  "notifications": true,
  "aur": {
    "qt_theming": { "qt6ct-kde": true }
  }
}
```

### Ownership boundaries

- The KDE adapter owns every KDE-ecosystem package: Plasma stack
  (hardcoded), KDE applications (`apps_list`), Plasma quality-of-life
  Qt plugins (`apps_list:plasma_extras`), Qt theming under non-KDE
  sessions when relevant (declared in the Hyprland adapter instead).
- Host configs declare nothing that is derivable from
  `environment.desktop`. They hold user-personal repo packages
  (browsers, dev tools, media players) and AUR additions.
- The line between "KDE package" and "user package" is "would
  selecting `kde` imply this?" If yes → adapter. If no → host config.

### Validation behaviour

- Shape violations (wrong depth, wrong leaf type, bad category name)
  → abort at config-load time before pacstrap, with a precise path
  in the error message.
- Empty categories are permitted (operator may stub out a category).
- Duplicate package strings across categories are silently deduped
  (cosmetic-only categorization).

### ADRs and CONTEXT.md

- ADR 0021: Desktop Environment Adapter owns all DE packages.
  Captures the ownership boundary and the host-config-declares-nothing
  principle.
- ADR 0022: Categorized list schema for package and adapter lists.
  Captures the 2-level rule, kebab-case categories, fail-fast
  validation, and the cosmetic-only semantics.
- `CONTEXT.md` updates (alongside the implementation PR, not before):
  - `Host Package List` — gains 2-level categorized shape definition.
  - `Desktop Environment Adapter` — gains `aur:` field, full ownership
    of DE packages.
  - `Environment Runner` — gains adapter-AUR discovery responsibility.

### Rollout (3 PRs)

1. **PR 1 — KDE app migration (data only).** Add the current
   `desktop/config.jsonc` KDE apps as defaults in
   `install-kde.jsonc:apps_list` (still flat at this stage). Strip
   the same packages from `hosts/desktop/config.jsonc`. No parser
   changes. Behaviour-preserving.
2. **PR 2 — Adapter ownership refactor.** Move
   `extra-cmake-modules` to Host Core `packages.repo`. Create the
   `cups` System Program; add to Host Core `system_programs`. Drop
   both from `kde.sh`. Trim `kde.sh`'s shell block to the hardcoded
   minimum. Add `plasma_extras` and friends to `apps_list`. Drop
   `install-kde.jsonc:extra`. Land ADR 0021.
3. **PR 3 — Categorized schema + adapter AUR.** Introduce the
   Categorized List Parser. Migrate `install-kde.jsonc:apps_list`,
   `hosts/core/config.jsonc`, `hosts/desktop/config.jsonc` to the
   categorized shape. Add `install-<de>.jsonc:aur` field; declare
   `qt6ct-kde` in Hyprland adapter. Teach Runner to read adapter AUR.
   Land ADR 0022 + `CONTEXT.md` updates.

## Testing Decisions

A good test here covers *external behaviour* of the parser and the
Runner's AUR merge, not the shape of internal jq pipelines.

### Categorized List Parser

Table-driven unit tests. Inputs: JSON value + leaf-type tag. Outputs:
either a sorted-unique flat list, or a non-zero exit with an error
message containing the offending path.

Coverage:
- Valid 2-level object with multiple categories → correct flat output.
- Valid object with empty category → category contributes nothing,
  no error.
- Valid object with duplicates across categories → output is deduped.
- Bool-mode input with mixed true/false → only `true` keys emitted.
- Bool-mode input with all-false categories → empty output, no error.
- Invalid: top-level array → error names "expected object".
- Invalid: depth 1 (string leaf at top) → error names "expected
  category".
- Invalid: depth 3 (object nested under category) → error names
  offending path.
- Invalid: category name `Browsers` / `media_apps` / `mediaapps!` →
  error names rejected key.
- Invalid: bool-mode value `"yes"` → error names leaf path and
  expected type.
- Invalid: string-mode value `true` → error names leaf path and
  expected type.
- Empty top-level object → empty output, no error.

Prior art: closest patterns in repo are the layout validator
(`layout_validate` in each layout module), which aborts via `error`
on first failure; and the `picker_validate_layout` check in
`tools/pick.sh`. Test harness can follow the bats style already
present under `.os/tests/`.

### Runner AUR Merge

Smoke test that exercises the Runner reading host AUR + adapter AUR
together. Should verify:
- With `environment.desktop=hyprland` and `qt6ct-kde` declared in
  `install-hyprland.jsonc:aur`, the resolved AUR set contains
  `qt6ct-kde`.
- With `environment.desktop=kde` (no AUR declared in
  `install-kde.jsonc`), the resolved AUR set contains only host AUR
  entries.
- With `environment.desktop=["kde","hyprland"]`, AUR from both
  adapters merges with host AUR; duplicates deduped.
- Adapter with no `aur:` field contributes nothing (no error, no
  warning).

This can be a Bash-level test against a fixture install config and
fixture adapter JSONC files — no actual paru invocation needed; the
test asserts on the resolved package list before pacstrap/paru runs.

Prior art: `.os/tests/` already has fixture-driven Bash tests; the
VM smoke tests under `tests/vm/` exist but are heavier than needed
here.

## Out of Scope

- Recursive categorization (more than 2 levels). Strict 2-level rule.
- Permissive parser accepting flat arrays alongside categorized
  objects. Single-shape rule.
- Categorization of `system_programs[]`. Stays flat — programs
  carry their category in the filesystem tree.
- Reorganising the existing program taxonomy under
  `.os/programs/<category>/`. The `cups` program follows existing
  conventions, nothing more.
- Changing `environment.desktop` resolution semantics.
- Re-evaluating the Display Manager auto-selection rule (KDE → SDDM,
  Hyprland-only → greetd). Untouched.
- Migrating User Config `programs[]` lists to a categorized shape.
  Programs are referenced by name only and are not the subject of
  this PRD.
- Adapter-installed AUR through any path other than the Runner's AUR
  pass (e.g. directly inside the adapter via a bootstrapped paru).

## Further Notes

- The `extra: []` field in `install-kde.jsonc` exists today but is
  unused in the live config. Removing it is a clean break, no
  migration burden.
- `kimageformats5` is borderline (Qt plugin, not strictly Plasma).
  Lands in `apps_list:plasma_extras` rather than the hardcoded
  minimum so operators can drop it without surgery.
- `qt6ct-kde` is named with a `-kde` suffix but its use case is
  "theme Qt apps outside Plasma" — i.e. Hyprland. It lives in the
  Hyprland adapter on purpose; do not move it to the KDE adapter on
  vibes.
- The Categorized List Parser is the only deep module here. The
  rest of the work is mechanical config movement and a small
  Runner change. Investing in good parser tests pays off because
  the parser is reused at four call sites.
- After PR 1, `hosts/desktop/config.jsonc` will contain only
  non-KDE packages. After PR 2, the KDE adapter is the
  single source of truth for KDE. After PR 3, all four schemas are
  uniform.

## Completion note

All 6 issues done; ADRs 0021/0022 landed; parser, adapter ownership,
`cups` System Program, categorized host/adapter lists, Runner AUR merge,
and CONTEXT.md all shipped. `octopi` migrated from host `packages.aur`
(desktop + laptop) into `install-kde.jsonc:aur` — it now installs only
when KDE is selected (PRD story 21 closed).

Deviation: category names in this PRD's examples use underscores
(`plasma_extras`, `qt_theming`, `file_management`). The Categorized List
Parser enforces kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`), so the shipped
config uses `plasma-extras`, `qt-theming`, etc.
