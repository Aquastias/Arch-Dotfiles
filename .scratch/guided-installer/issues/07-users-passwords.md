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

- [x] Operator can include existing committed user profiles and/or create
      ad-hoc users (full User Profile field set, defaulted from User
      Core).
- [x] The first selected user is marked the Primary User.
- [x] Root + user passwords are settable (user default `12345`); injected
      via decrypted-shape tmpfs + install-state, no SOPS, cleared per the
      existing lifecycle.
- [x] No password appears in a Saved profile or an Exported config.
- [x] bats: users-delta emit + the password tmpfs contract.
- [ ] VM smoke: a guided install with an ad-hoc user + set password boots
      and the user can log in. (Pending — needs a push + KVM run.)

## Blocked by

- `01-guided-install-tracer-bullet`
- Soft: `02-nav-reset-undo-redo` (form reset reuses the reset verbs)

## Comments

**Core DONE via /tdd (2026-06-20); VM smoke pending (needs a push + KVM).**

Pure cores (emit.sh): `guided_user_profile` — ad-hoc form → User Profile delta
over User Core (drops `name`, prunes empty/false/[]/{}, closed-schema-valid).
New `tests/config/guided-users.bats` (2).

No-SOPS password seam: new `lib/guided-secrets.sh:guided_write_passwords` writes
the decrypted shape (`host-secrets.json {root_password}`, `<name>-secrets.json
{password, ssh_identity_private_key?}`) to a tmpfs dir and records the paths in
install-state under **`.guided_passwords.*`** — NOT `.secrets.*`, which gates
implicit SOPS-program activation (ADR 0025). The two back-end resolvers now read
both keys: `chroot.sh:_chroot_resolve_host_secrets` (`.secrets.host //
.guided_passwords.host`) and `runner.sh:_profiles_resolve_user_secrets`
(likewise). New `tests/config/guided-secrets.bats` (3) + chroot-configure(+1) +
profiles-secrets(+1).

Guided shell (guided.sh): Users are the ordered union of committed picks
(`_guided_pick_users` fzf-multi over `users/*/`, excl. core) and ad-hoc creates
(`_guided_create_user` — name/shell/sudo/groups/programs/git/ssh-keys via the
seam → `guided_user_profile` delta), committed first, deduped — `users[0]` is the
Primary User. Passwords held aside (`_GUIDED_ROOT_PW`/`_GUIDED_USER_PW`, never the
Config State); `_guided_secrets_manifest` builds the no-SOPS manifest. At Proceed
`_guided_finalize_users` materializes ad-hoc `users/<name>/profile.jsonc` (live
clone; Save commits the same — issue 08) and writes the manifest to
`$GUIDED_SECRETS_MANIFEST`. guided-shell(+8).

Install wiring: `install.sh` stages+exports `GUIDED_SECRETS_MANIFEST` before
`guided_build`; `03-install.sh` (after `secrets_persist_state`) persists it via
`guided_write_passwords` into install-state, then wipes the staged plaintext
after `run_profiles`. Passwords never enter the Effective Config (integration
test asserts no leak).

Tests: +15 → full suite **1222 bats**, shellcheck clean (incl. install.sh /
03-install.sh). VM smoke (ad-hoc user + set password → boot + login) is the only
open box.
