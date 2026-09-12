# 02: Vendor and serve the mattpocock skills

**What to build:** Pi comes pre-loaded with the full mattpocock skill set on a
fresh install, with no network required at install time, and the operator can
refresh the skills later with one familiar command.

Scope: the full mattpocock/skills set is vendored (copied, not symlinked) into
`.agents/skills/` at the repo root, with the Vercel CLI's `.skill-lock.json`
committed as the pin. The tree is seeded into `/etc/skel` and stow-ready so it
lands at `~/.agents/skills/`, which pi auto-discovers with no `skills` settings
entry. Refresh is `npx skills@latest add mattpocock/skills` run in-repo, which
overwrites in place. Anchored by ADR 0127.

**Blocked by:** 01 (needs the installed pi + seed/stow config tree).

**Status:** ready-for-agent

- [ ] All mattpocock skills are vendored under `.agents/skills/` and committed.
- [ ] `.skill-lock.json` is committed alongside as the reproducible pin.
- [ ] The skills tree is seeded into `/etc/skel` and present in the stow tree.
- [ ] `pi-agent.bats` asserts the vendored skills + lockfile are present.
- [ ] On the `arch-combined` VM, pi discovers and loads the skills with no
      settings entry.
- [ ] Re-running `npx skills@latest add mattpocock/skills` in-repo overwrites the
      vendored skills (refresh works).
