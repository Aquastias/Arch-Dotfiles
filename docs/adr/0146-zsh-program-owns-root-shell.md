# ADR 0146: The zsh Program makes zsh root's shell, overriding `root_shell`

## Status
Accepted — implemented (`.installer/programs/system/zsh/install.sh`, commits
dd88560, 2d70da8). Amends ADR 0054 (Guided root shell): `options.root_shell`
only decides root's shell when the `zsh` User Program is not installed.
Glossary: [[Root Shell]], [[User Core]].

## Context
ADR 0054 lets the operator choose root's login shell (`bash` by default, or
`zsh`/`fish`). `lib/chroot/password.sh` applies it during `configure_system`.
Later, zsh became a fleet User Program in User Core (ADR 0129/0134). Its
install script seeds `/root` with the static zsh theme and the warmed zinit
cache, and gives root a red `root@host` prompt context, so a root shell is
never mistaken for a user shell. The Runner (`run_profiles`) runs after
`configure_system`, so the script's `chsh -s /usr/bin/zsh root` always wins.

## Decision
Accept the override. When the `zsh` Program is installed, root gets zsh with
the loud root prompt, whatever `options.root_shell` says. The root shell choice
still applies on hosts without the zsh Program (the Minimal Profile's `server`
user, the VM test users, or any host whose users exclude zsh).

## Considered Options
- **Make the zsh Program respect `root_shell`** (skip `chsh` unless the choice
  is zsh). Rejected: the red root context is the point of seeding `/root`, and
  a zsh fleet with a bash root loses that warning.
- **Change the ADR 0054 default to zsh.** Rejected: it would install zsh on
  hosts that don't ship the zsh Program.

## Consequences
- On a default host, the Guided `root shell` row does nothing unless zsh is
  deselected. It is not hidden or relabelled yet.
- Root never live-follows Noctalia: `/root` gets the static default theme,
  because Noctalia runs only in user sessions.
