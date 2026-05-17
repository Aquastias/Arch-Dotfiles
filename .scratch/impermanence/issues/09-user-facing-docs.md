Status: ready-for-agent

# User-facing docs for impermanence

## Parent

`.scratch/impermanence/PRD.md`

## What to build

The user-facing READMEs (`.os/README.md`, `.os/REFERENCE.md`) make no mention of impermanence, even though the feature is fully shipped (Slices 1–5). `CONTEXT.md` and `ADR-0008` cover the design; this issue covers operator-facing prose.

Scope:

- `.os/README.md`:
  - Section 4 (File Layout): add `lib/chroot/impermanence.sh`, `lib/impermanence-common.sh`, and the new `tools/impermanence.sh` to the tree.
  - Section 6 (Optional Components): add a row for `options.impermanence`, with a one-line description and a pointer to `REFERENCE.md`.
  - Section 8 (After Installation): add a bullet recommending `tools/impermanence.sh status` as a boot-time health check (surfaces missing `@blank` snapshots before the next reboot fail-closes).

- `.os/REFERENCE.md`:
  - `install.jsonc` reference: document `options.impermanence` (`enabled`, `dataset`, `mount`) under the `options` section.
  - New section "Impermanence" covering:
    - What it does (one paragraph; defer to ADR-0008 for the why).
    - Persist Extensions: how to declare paths under `persist.directories` / `persist.files` in a Host Config.
    - The runtime tool's four verbs (`add`, `remove`, `status`, `apply-defaults`) with one-line descriptions and example invocations.
    - Curated Persist Defaults: the fixed list, why operators cannot edit it directly, and the `apply-defaults` upgrade path after `git pull`.

- Cross-references: link from the new `REFERENCE.md` section to `ADR-0008` and `CONTEXT.md` for design rationale and glossary.

Out of scope:

- No design changes. This is documentation only.
- Do not modify `CONTEXT.md` or ADRs; they are already accurate.
- Do not add operator-facing examples that would require new code (e.g. `os impermanence` CLI wrapper — the tool is invoked directly today).

## Acceptance criteria

- [ ] `.os/README.md` File Layout tree includes the three impermanence source files
- [ ] `.os/README.md` Optional Components table has an `options.impermanence` row
- [ ] `.os/README.md` After Installation section mentions `tools/impermanence.sh status` as a health check
- [ ] `.os/REFERENCE.md` documents `options.impermanence` fields in the `options` reference
- [ ] `.os/REFERENCE.md` has an "Impermanence" section covering Persist Extensions, the four tool verbs, and Curated Persist Defaults
- [ ] `REFERENCE.md` cross-links to `ADR-0008` and `CONTEXT.md`
- [ ] No regression: existing bats suite still green (sanity check; this issue should not touch any code)

## Blocked by

- `.scratch/impermanence/issues/05-runtime-tool-status-apply-defaults.md` (now done)
