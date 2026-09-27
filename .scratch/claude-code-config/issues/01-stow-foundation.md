# 01: Stow foundation — make `~/.claude` stowable

**What to build:** The dotfiles repo becomes able to stow a Claude Code config
into `~/.claude/`, which today it cannot (the dir is gitignored). Negate
`.gitignore` so exactly three files are tracked — `.claude/settings.json`,
`.claude/CLAUDE.md`, `.claude/scripts/statusline.sh` — seeded with the operator's
*current* live content, while all runtime state and `.credentials.json` stay
ignored. `stow --no-folding .` then links the three into `~/.claude/` beside the
untracked state. Also fix the `CONTEXT.md` glossary entry that lists `.claude/`
as a Stow Tree dir, which contradicts `.gitignore`. This is the prefactor every
later ticket builds on; no behaviour changes yet (content is captured as-is).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] `.gitignore` tracks exactly `.claude/settings.json`, `.claude/CLAUDE.md`,
      `.claude/scripts/statusline.sh` and nothing else under `.claude/`
- [x] `git ls-files .claude` returns exactly those three paths
- [x] `.credentials.json`, `settings.local.json`, and Claude Code runtime state
      remain gitignored
- [x] `stow --no-folding .` links the three files into `~/.claude/` without
      clobbering untracked runtime state (adoption/backup of the pre-existing
      real files documented)
- [x] `CONTEXT.md` no longer mis-lists `.claude/` as a Stow Tree dir

## Comments

- 2026-09-27 doc sync: shipped in 6521bc3, 2bb7784, 6e78829, 2711118, 8d7adf8,
  0529dd6, 4039310, 88a7516, 1f74b30 (ADR 0133).
