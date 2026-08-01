# Root shell: guided cycle row → options.root_shell → chroot chsh

Status: done

## Parent

`.scratch/guided-encryption-passphrase-root-shell/PRD.md` (ADR 0054)

## What to build

Let the operator choose root's login shell in the Guided Installer, the same way
they choose a user's shell, and apply it to root at install time — without ever
leaving root with an unusable shell.

An operator on the Users screen sees a `root shell` row under `root password`,
cycles it through bash/zsh/fish, and the installed machine logs root into the
chosen shell. Leaving it alone keeps today's `/bin/bash`. Independent of the
encryption-passphrase tickets.

Reuses the shell-cycle helper the User Editor uses and the missing-login-shell
package-install guard from `create-user.sh`.

## Acceptance criteria

- [ ] A `root shell: <name>   (Enter cycles)` row renders on the Users screen
      directly under `root password`.
- [ ] Enter cycles `/bin/bash` → `/bin/zsh` → `/bin/fish` (same cycle helper as
      the user shell row).
- [ ] The choice writes Config State `options.root_shell` (default `/bin/bash`),
      normalised out when it equals the default, so it bakes into Export / a saved
      profile. The row is not gated.
- [ ] `lib/chroot/password.sh` sets root's login shell to the resolved
      `options.root_shell` via `chsh`, resolved host-side and passed in like
      `ROOT_PW`.
- [ ] A non-default root shell installs the shell's package first if absent,
      reusing the missing-login-shell guard pattern from `create-user.sh`, so root
      login can't break on a missing shell.
- [ ] `tests/config/guided-controller.bats`: the Users list shows
      `root shell: <name>`; Enter cycles bash→zsh→fish and writes
      `options.root_shell`, normalising the value out when it lands on the default.
- [ ] `tests/chroot/chroot-password.bats`: root's `/etc/passwd` shell ends up at
      the resolved `options.root_shell`; a non-default shell triggers the package
      install (guard prior art in `tests/chroot/chroot-create-user.bats`).
- [ ] VM (`arch-zfs-test-guided-secure` or an equivalent guided run):
      `options.root_shell` is observable as root's shell in the booted system.

## Blocked by

- None — can start immediately (independent of tickets 01 and 02).
