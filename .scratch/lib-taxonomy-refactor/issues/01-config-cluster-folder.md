Status: ready-for-agent

# Config cluster → lib/config/ (rename+move)

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Move and rename the Config cluster into a new `lib/config/` folder per
the approved mapping, update every `source`/path reference repo-wide,
and relocate these modules' tests to the mirrored `tests/config/` path.
Behavior-preserving: only file paths change.

Approved rename mapping:

```
config.sh            -> config/lifecycle.sh
  (load_config, detect_mode, print_summary, generate_template)
install-config.sh    -> config/accessors.sh   (install_config_*)
configs.sh           -> config/layers.sh      (core+specific merge,
                                                program registry/validation)
configs-generator.sh -> config/generator.sh   (cg_*)
categorized-list.sh  -> config/categorized-list.sh
validation.sh        -> config/validation.sh
environment.sh       -> config/environment.sh
```

Public function names stay stable — only the files move. Schema-driven
accessors (ADR 0015), categorized-list schema (ADR 0022), and
environment-resolution self-containment (ADR 0017) are preserved.

Also add the new ADR recording the `lib/` folder taxonomy and the
"folder needs ≥2 related files" rule (listing the root singletons:
`common`, `globals`, `jsonc`, `install-state`, `finalize`,
`grub-common`, `live-medium`, `secrets`, `impermanence-common`,
`picker`). Historical ADRs (0012–0031) are left untouched; new ADR
numbers continue from 0032.

## Acceptance criteria

- [ ] 7 config files moved+renamed into `lib/config/` per the mapping
- [ ] Every `source`/path reference to the old files updated repo-wide
- [ ] All public function names unchanged (`install_config_*`, `cg_*`,
      `load_config`, `detect_mode`, `print_summary`,
      `generate_template`, layer/validation/categorized-list functions)
- [ ] These modules' tests relocated to mirrored `tests/config/` paths
- [ ] Full bats suite passes unchanged (no behavior change)
- [ ] New ADR added: `lib/` folder taxonomy + ≥2-file rule + root
      singletons; historical ADRs untouched

## Blocked by

- None - can start immediately
