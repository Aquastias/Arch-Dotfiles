# ADR 0003: All installation happens during the live CD phase

## Status
Accepted

## Context
User-level programs (AUR packages, user-specific dotfiles) cannot be installed as root. The question was whether to install them during the live CD phase or via a first-boot setup script.

## Decision
All installation — system programs and user programs — happens during the live CD install, before the system is ever booted. User programs are installed via `arch-chroot /mnt su - <username>`. Paru is bootstrapped per user inside the chroot before any user programs are installed. No first-boot scripts are generated or dropped into user homes.

## Consequences
- User logs in to a fully configured system on first boot — no manual setup step
- Install time is longer (AUR builds happen during install)
- Paru must be buildable inside the chroot (requires `base-devel`, `git` in pacstrap packages)
- `arch-chroot /mnt su - <username>` is the mechanism for running user-context commands during install
