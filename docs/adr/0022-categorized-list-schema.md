# ADR 0022: Categorized list schema for package and adapter lists

## Status
Accepted.

## Context
Host configs and DE adapter configs declared package lists as flat
string arrays (`packages.repo`, `packages.aur`) and flat boolean maps
(`install-kde.jsonc:apps_list`). At ~150 entries per host, the
desktop `packages.repo` array read as one alphabetical wall of text —
no way to group `firefox` with `brave-bin` under "browsers" or
`steam` with `wine` under "gaming" for readability. The same
problem manifested in `apps_list`: twenty KDE apps, no grouping.

Operators wanted cosmetic grouping without changing what installs.
Permissively accepting both flat and categorized shapes would
double the parsing surface and let drift creep in (one host
categorized, another flat).

## Decision
Every list-of-strings or list-of-booleans field used to declare
packages becomes a strict 2-level object: `{ category: leaves }`.

Schema:

- Top-level is an object. Keys are kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`).
- For string-list fields (`packages.repo`, future `packages.aur`):
  values are arrays of strings.
- For toggle-map fields (`apps_list`, adapter `aur`): values are
  objects mapping leaf names to booleans.
- Depth is exactly two — no further nesting.
- Empty categories are permitted (stub a category, fill later).
- Duplicate leaves across categories are silently deduped.
- Categories are cosmetic — renaming `media` to `multimedia` does
  not change what gets installed.

A single Categorized List Parser
(`lib/categorized-list.sh::categorized_list_parse`) is reused at
every call site (pacstrap list builder today; adapter consumers in
the next slice). The parser is a pure function over JSON: input is a
JSON value plus a leaf-type tag (`"string"` or `"bool"`); output is
a sorted-unique flat list on stdout. Shape, leaf-type, or
category-name violations abort via the standard `error` helper at
config-load time, before pacstrap runs.

## Considered alternatives
**Permissive parser accepting flat arrays alongside categorized
objects.** Doubles parsing surface; lets new flat lists slip in.
Defeats the "uniform schema" goal.

**Recursive categorization (more than 2 levels).** Solves a problem
nobody has. Operators want one grouping level; nesting `media ›
video › vlc` produces no measurable benefit and complicates the
parser.

**Per-site bespoke parsers.** Four call sites means four places to
get validation wrong. The parser is the only deep module in this
PRD; investing in one shared parser pays off because the validation
rules are identical at every site.

**Run-time warning instead of fail-fast.** A typo in a category
name would only surface as "package not installed" after pacstrap
runs, hours into an install. Fail-fast at config-load time catches
operator typos before any disk work begins.

## Consequences
- `hosts/core`, `hosts/desktop`, `hosts/laptop` `packages.repo`
  reshaped to 2-level objects with operator-chosen category names.
  No change in installed package set.
- `lib/packages.sh` consumes the parser instead of inlining the
  `.packages.repo[]?` jq pipeline. `lib/categorized-list.sh` joins
  the source list in `03-install.sh`.
- The parser also services future call sites: `packages.aur`
  (issue 06), `install-kde.jsonc:apps_list` (issue 05), and adapter
  `aur:` fields (issue 06).
- Adding a new package category is one edit to the relevant
  config — no schema/parser change.
- Renaming a category is purely cosmetic — set membership is
  identical before and after.
- Operator-facing failure mode is now: error at config-load with a
  path like `packages.repo.media-Apps: invalid category name`.
  Cheaper to fix than a half-completed pacstrap.
