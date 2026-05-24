Status: ready-for-agent

# Variant Resolver: full logic + bats

## Parent

`.scratch/per-program-config-tree/PRD.md`

## What to build

Replace the slice-01 stub Variant Resolver with the full spec.

The resolver takes:

- merged user `variants` map (after the User Core + User Config
  deep-merge already performed by the Runner)
- the set of available variant directory names per program,
  discovered by walking `.os/programs/*/*/configs[@*]/`

and returns either:

- `{ program → resolved variant dir name }`, where the value is
  either `"configs"` or `"configs@<name>"`, or
- a list of operator-facing errors

Error cases enforced:

- Variant declared in user config but no matching `configs@<x>/`
  exists for that program
- Program has only `configs@*/` directories (no plain `configs/`)
  and the user did not declare a variant for it
- A `configs@default/` directory exists on disk (the literal
  `default` is reserved and refers to `configs/`)
- A variant directory name does not match `[a-z0-9-]+`

Schema additions: User Config and User Core both accept an optional
top-level `variants` object, string-to-string, keyed by program
name. Standard deep-merge applies per-key (not whole-object
replace). When `variants.<program>` is the literal string
`"default"`, the resolver selects `configs/`.

The merge logic itself reuses the existing User Core + User Config
merge function — this slice does not introduce a parallel merger.

## Acceptance criteria

- [ ] Resolver returns `configs` for every program when no
      `variants` key exists in either User Core or User Config
- [ ] Resolver returns the matching `configs@<x>/` when
      `variants.<program> = "<x>"` and that directory exists
- [ ] Resolver returns `configs` when `variants.<program> =
      "default"` (reserved name)
- [ ] Resolver errors when `variants.<program> = "<x>"` and no
      matching `configs@<x>/` exists
- [ ] Resolver errors when a program has only `configs@*/`
      directories and no variant was declared for it
- [ ] Resolver errors when a `configs@default/` directory exists on
      disk
- [ ] Resolver errors when a variant directory name violates
      `[a-z0-9-]+`
- [ ] User Core's `variants.<program>` is overridden by User
      Config's `variants.<program>` on a per-key basis, not
      whole-object replace (House Defaults pattern)
- [ ] `configs-variant-resolver.bats` covers every case above with
      fixture inputs; all bats pass
- [ ] `tests/audit.sh` still passes

## Blocked by

- `01-tracer-end-to-end-pipeline.md`
