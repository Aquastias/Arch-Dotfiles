Status: done

# Migrate remaining simple config Programs to `home/`-only

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

Move the straightforward config-bearing Programs onto the single-source,
decoupled model established by the tracer: `lazygit`, `yazi`, `pi`, `claude`,
`teamspeak3`. For each, config lives only under the Program's `home/`, the
repo-root copy (if any) is deleted, and `install.sh` installs the package /
does genuine setup only — no `$HOME` config seeding. `teamspeak3`'s static
add-ons/themes move into `home/.ts3client/`; anything genuinely generated stays
in `install.sh`.

## Acceptance criteria

- [ ] Each listed Program's config lives only under its `home/`; no repo-root
      duplicate remains.
- [ ] Each listed `install.sh` no longer seeds config into `$HOME` (package /
      system setup only).
- [ ] Each Program's config is applied by the Runner pass and by
      `./stow-configs`, and is skippable via `config_exclude` / `--except`.
- [ ] `teamspeak3` static add-ons/themes stow from `home/`; the client lands
      styled without an `install.sh` copy.
- [ ] VM harness confirms each Program installs and configures as before when
      not excluded.

## Blocked by

- `01-tracer-decouple-config-apply-kitty.md` (the apply pass must exist).
