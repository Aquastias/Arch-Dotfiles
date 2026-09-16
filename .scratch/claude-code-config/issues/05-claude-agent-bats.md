# 05: Static seam — `claude-agent.bats`

**What to build:** A static test that proves, without a real install, that the
Claude Code program is correctly packaged, wired, and stow-shaped — catching
packaging/stow/settings drift cheaply. Modeled on `pi-agent.bats` /
`noctalia-stow.bats`.

**Blocked by:** 04.

**Status:** ready-for-agent

- [ ] `dev/claude` program config validates and resolves into the desktop +
      laptop effective config
- [ ] `claude-code`, `bubblewrap`, `socat`, `github-cli`, `ccusage` resolve for
      those hosts
- [ ] Stow tree carries the three tracked files, with pinned settings keys
      asserted (attribution empty, `defaultMode: auto`, libvirt socket,
      `claude-opus-4-8`)
- [ ] `.gitignore` tracks exactly the three files and still excludes
      `.credentials.json` + runtime state
- [ ] Seed payload (`.installer/programs/dev/claude/`) is byte-identical to the
      stow copy (`.claude/`)
- [ ] `CONTEXT.md` no longer lists `.claude/` as a Stow Tree dir
- [ ] Lives under `.installer/tests/config/`
