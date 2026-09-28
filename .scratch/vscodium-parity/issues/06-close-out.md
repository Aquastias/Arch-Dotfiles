# 06: Close-out — full VM acceptance + docs

**What to build:** One full VM acceptance pass of the finished [[VSCodium
Config]] and docs brought to reality: ADR 0148 status → implemented (with any
surround/Vue/phpactor/palette outcomes folded in), glossary entries checked
against what shipped, spec status → done.

**Blocked by:** 03 (Languages), 04 (Keymaps), 05 (Debuggers).

**Status:** done

- [x] VM: fresh install with vscodium selected; extensions, system servers,
      format on save, key spot-checks, one breakpoint, screenshot
- [x] Full bats suite + shellcheck + no-python green
- [x] ADR 0148 status updated; gaps/exceptions list matches what shipped
- [x] CONTEXT.md entries match; SPEC.md status: done

## Comments

- VM (fresh arch-combined, niri, local repo via REPO_URL; claude excluded
  VM-only — ccusage failed AUR vetting, needs an interactive re-pin):
  - 32/32 extensions (+ ms-python.vscode-python-envs, a python dependency).
  - settings/keybindings byte-identical to repo for user + /etc/skel.
  - Running servers: /usr/bin/rust-analyzer, /usr/bin/biome.
  - Format on save via `<leader>w`: TS (biome, tabs), Rust (rustfmt).
  - Surround `gsa`/`gsd`/`gsr` work. `<leader>uC`, `<leader>gg` (lazygit),
    `<leader>ff`, `-`, `<Esc>` :nohl work.
  - debugpy breakpoint hit via `<leader>db` + `<leader>dl`; `dc` continues.
  - codelldb adapter downloaded at first activation (ok).
  - Sapphire accent compiled (#74c7ec).
  - Found + fixed: empty secondary sidebar on the left → hidden by default.
  - Workspace trust (Restricted Mode) kept as upstream default; ADR notes it.
- Full bats: only the 4 pre-existing failures (initcpio x3, claude-agent
  settings drift) that also fail on a clean tree. shellcheck: only the
  pre-existing menu.sh SC2016 info.
