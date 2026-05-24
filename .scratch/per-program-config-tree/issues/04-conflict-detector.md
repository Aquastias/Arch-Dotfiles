Status: ready-for-agent

# Conflict Detector: atomic-migration safety

## Parent

`.scratch/per-program-config-tree/PRD.md`

## What to build

Replace the slice-01 stub Conflict Detector with the full spec, and
wire it into the Generator CLI so a detected conflict aborts the
render.

Inputs:

- the Plan Builder's output for one user
- the legacy Stow Tree root (`~/.dotfiles`)
- the set of legacy stow packages the Runner passes to its first
  `stow` invocation today (e.g. `.config`, `.zsh`, `.claude` plus
  any home-relative loose files)

The detector walks each plan entry's `dst` (the destination the
generated stow tree will own once stowed) and checks whether the
same `$HOME`-relative path is already owned by any legacy stow
package. Output: list of conflicts where each entry names the plan
source path and the legacy source path.

Generator CLI behavior: when the conflict list is non-empty, the
generator aborts before any materialization with a single error
that names both source paths for every conflict, plus a one-line
explanation that the operator must delete one source to resolve.
Exit code is non-zero.

The legacy-package list must be read from the same source the
Runner uses — it must not drift. If the Runner exposes the list
via an env var or shared helper, reuse it; otherwise extract a
small accessor both call.

The error message must use the same `print_status` family already
used in the chroot orchestrators.

## Acceptance criteria

- [ ] Detector returns empty when no plan `dst` overlaps any legacy
      stow package's contents
- [ ] Detector flags a conflict when a plan `dst` matches a path
      already present under a legacy stow package
      (e.g. plan emits `.config/kitty/kitty.conf` and
      `.dotfiles/.config/kitty/kitty.conf` exists)
- [ ] Detector does NOT flag a conflict when the plan and a legacy
      package own paths with the same suffix but in different
      packages (e.g. plan emits `.config/foo` and legacy
      `.zsh/foo` both exist — different stow packages, no actual
      collision)
- [ ] Generator CLI aborts with non-zero exit when the detector
      returns conflicts; no `.stow/<u>/` writes occur in that run
- [ ] Error message names BOTH source paths for each conflict
- [ ] The legacy-package list consumed by the detector comes from
      the same source the Runner uses (no duplicated list literal)
- [ ] `configs-conflict-detector.bats` covers clean, single
      conflict, multi-conflict, and the same-suffix-different-
      package non-conflict; all bats pass
- [ ] `tests/audit.sh` still passes

## Blocked by

- `01-tracer-end-to-end-pipeline.md`
