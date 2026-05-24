Status: ready-for-agent

# Tracer: end-to-end pipeline, one program one file

## Parent

`.scratch/per-program-config-tree/PRD.md`

## What to build

The thinnest possible end-to-end slice of the Config Generator
pipeline. One fixture program with a single-entry `manifest.jsonc`
in its `configs/` dir gets materialized into a Generated Stow Tree
at `~/.dotfiles/.stow/<user>/` and stowed into `$HOME`.

All five logic modules ship as minimal implementations covering
only the happy path:

- **Variant Resolver** returns `configs` for every program when no
  `variants` key is declared anywhere. No error cases yet.
- **Manifest Validator** parses JSONC and asserts the top-level
  `files` array exists with `{ src, dst }` entries. Other rules are
  not enforced yet — they land in slice 03.
- **Plan Builder** turns one resolved manifest into plan entries
  `{ src_abs, dst_in_stow_tree, mode? }`. Single program, single
  user. Multi-program and system-program-per-user land in slice 05.
- **Conflict Detector** returns empty. Real detection lands in
  slice 04.
- **Materializer** copies `src_abs` to `dst_in_stow_tree`, creating
  intermediate dirs. Applies `mode` when present.

**Generator CLI** at `.os/tools/generate-configs.sh` accepts
`--user <name>` only (flags `--dry-run` / `--validate-only` land in
slice 06). Discovers programs by walking
`.os/programs/*/*/configs/`.

**Runner integration** in `.os/lib/profiles.sh`: after the existing
`_profiles_clone_dotfiles` call for each user and before the
existing `stow --no-folding */`, invoke the generator inside
`arch-chroot`. Then run a second stow against the generated tree:

```
stow -d ~/.dotfiles --no-folding .config .zsh .claude   # existing
stow -d ~/.dotfiles/.stow/<u> --no-folding .             # added
```

Exact legacy package list passed to the first stow is whatever the
Runner does today — this slice does not change it.

A fixture program (e.g. `.os/programs/_fixture/hello/configs/`
with one tiny file mapped to `~/.config/hello/greeting`) lives in
the test tree so subsequent slices can reuse it.

## Acceptance criteria

- [ ] `.os/tools/generate-configs.sh --user <u>` runs end-to-end
      against the fixture program and produces
      `~/.dotfiles/.stow/<u>/.config/hello/greeting`
- [ ] Runner integration: per-user generator invocation runs inside
      `arch-chroot` between the dotfiles clone and the second stow
- [ ] Second `stow -d ~/.dotfiles/.stow/<u> --no-folding .` runs
      after the first; both stow invocations succeed
- [ ] `$HOME/.config/hello/greeting` exists as a stow symlink after
      install
- [ ] One happy-path bats per module exists under `.os/tests/`,
      named `configs-variant-resolver.bats`,
      `configs-manifest-validator.bats`,
      `configs-plan-builder.bats`,
      `configs-conflict-detector.bats`
- [ ] All bats pass via `.os/tests/run.sh` (or equivalent existing
      runner)
- [ ] `tests/audit.sh` still passes (no name collisions with
      Shell Stdlib helpers)

## Blocked by

None — can start immediately.
