# 04: `dev/claude` install program + fleet wiring

**What to build:** Claude Code installs and self-configures on a fresh build,
the way pi does. A new `dev/claude` User Program installs the agent plus the
packages its sandbox and statusline need, seeds the `~/.claude/` payload, and is
wired into the fleet so every user on desktop and laptop receives it. Auth stays
a per-machine `/login`; no token is ever seeded.

**Blocked by:** 02, 03 (the seed payload must be byte-identical to the finalized
repo `.claude/`).

**Status:** done

- [x] `config.jsonc` (`kind: user`) and `install.sh` under
      `.installer/programs/dev/claude/`, following `PROGRAM_SPEC.md` and the
      `dev/pi` shape
- [x] Installs `claude-code`, `bubblewrap`, `socat`, `github-cli`, `ccusage`
      via the AUR Helper (`--needed`)
- [x] Seeds the payload into `~/.claude/` (`cp -r`), payload byte-identical to
      the repo `.claude/` stow copy
- [x] `.credentials.json` never written by the installer; success message notes
      `/login` on first run
- [x] `claude` appended to User Core `programs` (beside `pi`), so desktop +
      laptop resolve it
- [x] Installer seeds only — never stows (ADR 0095)

## Comments

- 2026-09-27 doc sync: shipped in 6521bc3, 2bb7784, 6e78829, 2711118, 8d7adf8,
  0529dd6, 4039310, 88a7516, 1f74b30 (ADR 0133).
