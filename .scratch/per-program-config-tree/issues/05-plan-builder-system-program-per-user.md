Status: ready-for-agent

# Plan Builder: multi-program + system-program-per-user

## Parent

`.scratch/per-program-config-tree/PRD.md`

## What to build

Replace the slice-01 single-program Plan Builder with the full
spec.

Inputs:

- the resolved variant map from the (real) Variant Resolver
- per-variant manifest contents (already validated)
- target stow root path (e.g. `~/.dotfiles/.stow/<user>`)
- the user being planned for, and the Host Config + User Config
  merge state needed to know which programs apply

Output: a flat list of plan entries
`{ src_abs, dst_in_stow_tree, mode? }`. No writes.

Rules the Plan Builder must enforce:

- For each **User Program** declared in the merged User Core +
  User Config, include the plan entries from that program's
  resolved variant manifest
- For each **System Program** declared in the merged Host Core +
  Host Config that has a `configs/` (or `configs@*/`) tree,
  include its plan entries for THIS user, using THIS user's
  variant selection (or the program's default if none)
- `dst_in_stow_tree` is the manifest's `dst` with the leading `~/`
  stripped and re-rooted under the target stow root (so
  `~/.config/foo/bar` becomes `<stow_root>/.config/foo/bar`)
- `mode` passes through when present, omitted when not
- Plan entries are returned in deterministic order so two runs
  with the same inputs produce byte-identical plans (helps
  `--dry-run` diffs in slice 06)

This is the slice that materializes user stories 17 and 18: a
system program with a `configs/` tree applies to every user on the
host, each picking their own variant. The Variant Resolver from
slice 02 already produces a per-user resolved map; the Plan Builder
consumes that and the host's system-program list.

## Acceptance criteria

- [ ] Plan for a single user-program produces one entry per
      manifest file
- [ ] Plan correctly selects the per-user variant for each program
- [ ] System program declared in Host Config with `configs/` is
      included in the plan for every user on the host
- [ ] Two users on the same host with different variants of the
      same system program produce different plans (each gets their
      own variant)
- [ ] System program with NO `configs/` (or `configs@*/`) is not
      included in any user's plan
- [ ] `mode` passes through unchanged when present in the manifest
- [ ] `dst_in_stow_tree` correctly strips `~/` and roots under the
      target stow root
- [ ] Two runs with identical inputs produce byte-identical plan
      output (deterministic order)
- [ ] `configs-plan-builder.bats` covers all cases above with
      fixture host configs and programs; all bats pass
- [ ] `tests/audit.sh` still passes

## Blocked by

- `02-variant-resolver.md`
