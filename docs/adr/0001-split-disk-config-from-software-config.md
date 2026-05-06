# ADR 0001: Split disk config from software config

## Status
Accepted

## Context
The original `install.jsonc` mixed disk/ZFS/locale concerns with user creation and package lists. A new declarative layer (host/user/program configs) was needed for software configuration.

## Decision
`install.jsonc` is restricted to live-CD-time concerns: disk layout, ZFS topology, partitioning, bootloader, locale, timezone, keymap, hostname. All software configuration (users, programs) moves to the host/user/program config layer under `.os/hosts/`, `.os/users/`, `.os/programs/`.

## Consequences
- `install.jsonc` drops its `users` and `packages` sections
- hostname in `install.jsonc` implicitly links to `.os/hosts/<hostname>/config.jsonc`
- Missing host config is a warning, not an error — install proceeds without the software layer (backward compatibility)
- The two configs are read at different phases: `install.jsonc` at partition time, host/user/program configs after pacstrap
