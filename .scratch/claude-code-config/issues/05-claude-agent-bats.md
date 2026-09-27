# 05: Static seam — `claude-agent.bats`

**What to build:** A static test that proves, without a real install, that the
Claude Code program is correctly packaged, wired, and stow-shaped — catching
packaging/stow/settings drift cheaply. Modeled on `pi-agent.bats` /
`noctalia-stow.bats`.

**Blocked by:** 04.

**Status:** done

- [x] `dev/claude` program config validates and resolves into the desktop +
      laptop effective config
- [x] `claude-code`, `bubblewrap`, `socat`, `github-cli`, `ccusage` resolve for
      those hosts
- [x] Stow tree carries the three tracked files, with pinned settings keys
      asserted (attribution empty, `defaultMode: auto`, libvirt socket,
      `claude-opus-4-8`)
- [x] `.gitignore` tracks exactly the three files and still excludes
      `.credentials.json` + runtime state
- [x] Seed payload (`.installer/programs/dev/claude/`) is byte-identical to the
      stow copy (`.claude/`)
- [x] `CONTEXT.md` no longer lists `.claude/` as a Stow Tree dir
- [x] Lives under `.installer/tests/config/`

## Comments

- 2026-09-27 audit: 8d7adf8, 4039310 (tests/config/claude-agent.bats; green
  2026-09-27).
