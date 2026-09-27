# Confirm already-cohesive tools (htop, git/less/ripgrep/fd); neovim untouched

Status: done

## Parent

SPEC: `.scratch/tui-theme-cohesion/SPEC.md` · ADR 0132. Glossary:
[[ANSI-16 Following]].

## What to build

Close out the tools that need no config change, and lock in the two guardrails
around them.

- **htop** — `color_scheme=0` (Default) already renders through the terminal's
  ANSI palette, so it coheres for free. `htoprc` is **runtime-rewritten** by
  htop on clean exit, so it must **not** be stowed (a stow symlink would clobber
  the repo — the generated-file ban, ADR 0104). No file is shipped.
- **git diff / less / ripgrep / fd** — confirm they render default ANSI (so they
  already follow the terminal palette); make no change.
- **neovim** — explicitly out of scope; its rose-pine colorscheme is left
  untouched.

## Acceptance criteria

- [x] Documented confirmation that htop Default (`color_scheme=0`) follows the
      terminal ANSI palette, and that no `htoprc` is stowed or seeded.
- [x] A guard asserts no `htoprc` is present in the stow tree (never stow a
      runtime-rewritten file).
- [x] Documented confirmation that git diff / less / ripgrep / fd render default
      ANSI with no change.
- [x] neovim config is unchanged (rose-pine intact).
- [ ] VM check: htop and a `git diff` track a Noctalia palette change on a
      compositor and stay Sapphire under KDE.

## Blocked by

None - can start immediately.

## Comments

- 2026-09-27 audit: eca3e60 (ADR 0132 records the confirmations). Later: neovim
  replaced by the served config (ADR 0135/0136). VM check not recorded — left
  unticked.
