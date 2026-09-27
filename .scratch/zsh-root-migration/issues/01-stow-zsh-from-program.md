# Stow zsh from its Program home/, drop repo-root twins

Status: done
Category: enhancement

## What to build

Host `~` still symlinks zsh config to pre-ADR-0134 repo-root copies
(`~/.zshrc -> .dotfiles/.zshrc`, etc.). Program copies under
`.installer/programs/system/zsh/home/` are the source of truth (ADR 0134);
root twins are byte-identical and must be hand-synced meanwhile.

1. Move `.zprofile`, `.zlogin`, `.zlogout` (root-only, no program copy)
   into the zsh Program `home/`.
2. Drop root `~` symlinks, run `dstow zsh`.
3. Delete root twins: `.zshrc`, `.zshenv`, `.zprofile`, `.zlogin`,
   `.zlogout`, `.zsh/`, `.zsh_aliases`, `.p10k.zsh`.

## Acceptance criteria

- [ ] `~` zsh files link into `.installer/programs/system/zsh/home/`
- [x] No zsh dotfiles at repo root
- [ ] `stow -n` for zsh reports no conflicts
- [ ] New shell starts clean; `dstow` alias resolves

## Comments

- 2026-09-27: repo side done — .zprofile/.zlogin/.zlogout moved into the
  zsh Program home/, repo-root twins deleted, zsh-program.bats now asserts no
  twin is tracked. The ~ relink (stow-configs.sh zsh) must be run by the
  operator; the ~-side lines stay unticked until then.
