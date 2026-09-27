# Collapse the package slots

Status: done

## Parent

.scratch/layered-software-model/PRD.md (R1)

## What to build

Two of the seven authored package slots are redundant. Remove them so there is
exactly one list for repo packages and one for AUR.

`packages.groups` is dead — no committed profile uses it, and its only writers
are the internal GPU and audio buckets. Those move out of the `packages`
namespace into a clearly-derived one, and become an error if authored, so a
derived set can never again be mistaken for something the operator declares.

`packages.extra` is `packages.repo` without a category. Remove it; the Guided
Installer's "extra packages" row writes into a `packages.repo` category
instead. The row's behaviour from the operator's side is unchanged — type a
package name, it gets installed.

Both keys leave the closed schema, so a profile still naming one aborts at load
with its path rather than silently doing nothing.

Also land a one-line live bug fix while the Base Package List is open: `stow`
joins it. The Runner invokes `stow` unconditionally for every user during the
dotfiles step, but no layer guarantees it — only the two host profiles happen
to declare it, so any host that doesn't (all three VM fixtures) hits
`stow: command not found`.

## Acceptance criteria

- [x] `packages.groups` is gone from the schema, accessors, package collection,
      and the install summary
- [x] `packages.extra` is gone from the schema, accessors, and package collection
- [x] The guided extra-packages row writes into a `packages.repo` category
- [x] Typing a package name in that row still results in it being installed
- [x] The GPU and audio derived buckets no longer live under `packages`
- [x] Authoring the derived bucket in a profile aborts at config load
- [x] A profile naming `packages.extra` or `packages.groups` aborts with the path
- [x] `stow` is in the Base Package List
- [x] `desktop` and `laptop` resolve to the same package set as before this change

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 audit: 43f6fe4.
