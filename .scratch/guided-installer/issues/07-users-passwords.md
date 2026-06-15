# Users — pick committed + ad-hoc + passwords

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

The **Users** section. Manage-users is an fzf-multi over committed
`users/*/` profiles **plus** a "create new" form that authors a User
Profile ad-hoc: name, shell, sudo (→ `wheel`), groups, programs (fzf
multi), git name/email, `ssh_authorized_keys`. The first selected user is
marked the **Primary User** (AUR/paru user + default pool owner).

Passwords are settable in the TUI — root and per-user (default user
password `12345`). On **Proceed**, the Guided Installer writes the
*decrypted* secrets shape (`{root_password}`, per-user `{password,
ssh_identity_private_key?}`) to tmpfs and points the Runner at it via
install-state — the same downstream contract the Secrets Module produces,
**without SOPS**. Install-time only; never written by Save or Export.

## Acceptance criteria

- [ ] Operator can include existing committed user profiles and/or create
      ad-hoc users (full User Profile field set, defaulted from User
      Core).
- [ ] The first selected user is marked the Primary User.
- [ ] Root + user passwords are settable (user default `12345`); injected
      via decrypted-shape tmpfs + install-state, no SOPS, cleared per the
      existing lifecycle.
- [ ] No password appears in a Saved profile or an Exported config.
- [ ] bats: users-delta emit + the password tmpfs contract.
- [ ] VM smoke: a guided install with an ad-hoc user + set password boots
      and the user can log in.

## Blocked by

- `01-guided-install-tracer-bullet`
- Soft: `02-nav-reset-undo-redo` (form reset reuses the reset verbs)
