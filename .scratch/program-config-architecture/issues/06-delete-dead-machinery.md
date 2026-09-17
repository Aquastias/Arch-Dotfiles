Status: ready-for-agent

# Delete dead machinery (ADR 0012 generator, `.stow`, drift test)

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

Remove the superseded and now-unused apparatus once every config-bearing
Program is single-sourced under `home/`: `lib/config/generator.sh`,
`tools/generate-configs.sh`, the Runner's `stow -d $DOTFILES/.stow/<user>` line
and the `.stow/` gitignore entry, and the `home/`-vs-repo-root drift test.

## Acceptance criteria

- [ ] `lib/config/generator.sh` and `tools/generate-configs.sh` deleted, with no
      remaining references (matrix, tests, runner).
- [ ] The `.stow/<user>` stow invocation and `.stow/` gitignore entry removed.
- [ ] The drift test removed; no Program still relies on a repo-root config
      copy.
- [ ] Test suite green after removal.

## Blocked by

- `04-migrate-simple-config-programs.md`
- `05-migrate-zsh.md`

(The drift test guards exactly the Programs those migrate.)
