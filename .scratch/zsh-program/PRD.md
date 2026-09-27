# PRD: zsh as a fleet-served Program (retroactive)

Status: done

Retroactive record — shipped without a grill session. Anchored by
[[ADR 0129]] (zsh follows Noctalia via user-template) and [[ADR 0134]]
(per-program `home/`).

## What shipped

- zsh provisioned by the installer as a stowable Program
  (`.installer/programs/system/zsh/`), live Noctalia palette via
  user-template; NVM_DIR + pkgfile timer set at install.
- p10k prompt: node/go/rust/swift/php/lua/typescript/cc/laravel segments with
  nerd-font icons, `os_icon`, git branch icon; swift gated to swift projects;
  nvm segment hidden for system node.
- eza file-type icons, bat palette-following ansi theme, fzf menu bg matches
  terminal.
- Root shell seeded with a loud red `root@host` context (powerline lock glyph).
- Cleanup: load order, history params, command-shadowing aliases, pruned
  plugins/exports; tree+pnpm shipped for their aliases; `dstow` alias.

## Commits

ad10b0f, bcf750a, dd5bb45, 4cb439d, a395e19, f0f1856, de49060, 1ecf427,
d53deec, fd78b44, 6ea4986, 4a86a39, 0330672, 1193ea2, 0e369c6, e850b78,
dd88560, 2d70da8, db0b4b5, 3c4b8c1, 2892543, 5dedcde.

## Decision record

Root-shell override accepted in [[ADR 0146]].

## Follow-up

Repo-root zsh twins still exist — `.scratch/zsh-root-migration/`.
