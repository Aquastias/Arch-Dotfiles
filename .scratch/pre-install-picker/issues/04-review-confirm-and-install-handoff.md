Status: done

# Review-confirm screen, edit loop, and install hand-off

## Parent

`.scratch/pre-install-picker/PRD.md`

## What to build

Add the final UX layer: a review screen that always renders before
writing, a four-way prompt, and the optional hand-off to
`install.sh`. After this slice the picker matches the Pre-Install
Picker term in CONTEXT.md end-to-end.

The slice does not touch the deep modules from slices 1–3 — it wires
new shallow glue around the existing pipeline.

### Review screen

After the Config assembler returns the assembled JSONC and the
existing `lib/install-config.sh` validation passes, render a review
screen showing the JSONC that will be written. When
`.os/install.jsonc` already exists, render a diff against it (plain
`diff -u` is fine; the goal is operator-readable, not pretty). When
no prior file exists, fall back to printing the JSONC itself.

The same review flow runs whether or not a prior `install.jsonc`
exists — no hidden conditional branch.

### Four-way prompt

After the review block, prompt the operator with the canonical
four-way choice:

- `[w]rite & install` — write `.os/install.jsonc`, then `exec
  install.sh` in the same shell.
- `[w]rite only` — write `.os/install.jsonc` and exit cleanly.
- `[e]dit` — re-enter the picker pipeline at the most recently
  relevant prompt (host / mode / disks) so the operator can correct
  a mistake without re-running from scratch.
- `[a]bort` — exit non-zero without writing.

### Edit loop

The `[e]dit` action returns to the prompt that produced the value
the operator most likely wants to change. A simple, predictable
ordering is enough — e.g. re-run mode → disks (host change is rare
and the operator can `[a]bort` and re-run instead). Whatever shape
the implementer chooses, document it in the script header.

### Install hand-off

`[w]rite & install` calls `exec install.sh` (no subshell) so that
control passes cleanly to the installer and the picker process is
replaced. `install.sh` remains unmodified.

## Acceptance criteria

- [ ] Review screen renders before any write, regardless of
      whether `.os/install.jsonc` exists.
- [ ] When a prior `install.jsonc` exists, the review screen shows
      a diff against it.
- [ ] Four-way prompt accepts `w` (write & install), `W` (write
      only — or another distinct key the implementer chooses; the
      surface is `[w]rite & install / [w]rite only / [e]dit /
      [a]bort`), `e`, `a`. Unrecognised input re-prompts.
- [ ] `[w]rite & install` writes the file then execs `install.sh`
      in the same shell.
- [ ] `[w]rite only` writes the file and exits zero.
- [ ] `[e]dit` re-enters the pipeline at a documented re-entry
      point and lets the operator change inputs without losing
      progress on unchanged prompts.
- [ ] `[a]bort` exits non-zero and does not modify
      `.os/install.jsonc`.
- [ ] `install.sh` is unchanged by this slice.
- [ ] No new deep modules; no slice 1–3 tests need updating.
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass.

## Blocked by

- `.scratch/pre-install-picker/issues/02-fzf-with-preview.md`
