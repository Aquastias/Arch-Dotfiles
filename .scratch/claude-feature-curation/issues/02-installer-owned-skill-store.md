# 02: Installer-owned skill-store bootstrap

**What to build:** A fresh build provisions the Matt Pocock skill store itself,
so "keep all skills" is reproducible instead of a manual step. The `dev/claude`
program's `install.sh` runs the Vercel `skills` CLI to install the store from
current upstream (which also resolves the operator's stale `to-prd`→`to-spec`
and `to-issues`→`to-tickets` renames), and the test seam proves the wiring.

Edits:
- `.installer/programs/dev/claude/install.sh` — add a guarded bootstrap step
  running `npx skills@latest add mattpocock/skills` as the owning user
  (populates `~/.agents/skills` + writes `~/.skill-lock.json`). Guard so a
  re-run / offline build degrades gracefully.
- Ensure `nodejs` + `npm` are available for `npx` — add `npm` to the program's
  installed packages if `claude-code` does not already pull it.
- `.installer/tests/config/claude-agent.bats` — assert `install.sh` invokes
  `npx skills@latest add mattpocock/skills` and that `npm`/`nodejs` is in the
  deps list.

Note for the implementer: the skill store is a regenerable runtime asset (never
tracked, like a package), so bootstrapping it in `install.sh` is consistent with
ADR 0134's package-only rule — but confirm that framing against the existing
"install.sh does NOT seed config" tests, and adjust their wording if the npx
step trips their intent. Consider a dedicated post-install step if `install.sh`
placement proves wrong.

**Blocked by:** 01 (shares the `claude-agent.bats` file; serialized to avoid an
edit conflict — not a logical gate).

**Status:** ready-for-agent

- [ ] `install.sh` runs `npx skills@latest add mattpocock/skills` as the owning
      user, guarded against re-run/offline failure
- [ ] `nodejs`/`npm` guaranteed present (added to deps if not already pulled)
- [ ] Existing "install.sh does NOT seed config / never writes credentials"
      tests still pass (or are reconciled with documented rationale)
- [ ] `claude-agent.bats` asserts the npx invocation + the npm/nodejs dep
- [ ] `bats .installer/tests/config/claude-agent.bats` passes; no-python green
