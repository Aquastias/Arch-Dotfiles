# Create cups System Program; register in host core

Status: ready-for-agent

## Parent

`.scratch/package-list-categorization/PRD.md`

## What to build

A new System Program at `.os/programs/<category>/cups/` containing
`config.jsonc` (with `"system": true`) and `install.sh`. The install
script installs the `cups` package via pacman and enables
`cups.service`. The program is listed in
`hosts/core/config.jsonc:system_programs` so every host gets the
print daemon by default, independent of desktop environment.

Category placement under `.os/programs/` should follow existing
conventions in the repo (e.g. `system` or whatever category houses
similar service-enabling programs — match the existing taxonomy
rather than introducing a new one).

This issue does NOT change `kde.sh`. The `cups` package will continue
to be installed there until issue 03 removes it; the System Program
makes `cups` available system-wide without duplicating the install.

## Acceptance criteria

- [ ] `.os/programs/<existing-category>/cups/config.jsonc` exists with
      `"system": true` and a display name.
- [ ] `.os/programs/<existing-category>/cups/install.sh` installs
      `cups` via pacman and runs `systemctl enable cups.service`.
- [ ] `hosts/core/config.jsonc:system_programs` includes `cups`.
- [ ] A fresh install on any host has `cups.service` enabled at first
      boot.
- [ ] `kde.sh` is unchanged.

## Blocked by

None - can start immediately.
