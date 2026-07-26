# Guided in-menu encryption passphrase + root shell

---
Status: accepted
---

The Guided Installer now captures the **ZFS/LUKS encryption passphrase inline in
the menu**, the same inline-masked way it already captures the root and per-user
passwords (ADR 0051), and lets the operator **set root's login shell** from the
Users screen. Both extend the existing guided credential/user surface rather than
add new machinery.

## Encryption passphrase

A **`encryption password`** row lands on the **Disks** screen directly under the
`encryption` toggle, shown **only when encryption is on**. It reads
`(not set) ⚠` / `(set)` — the `_ctl_secret_state` visibility already used for the
root/user password rows, never the value. Enter opens the **same inline-masked
secret screen** as passwords (type-twice confirm, masked bullets, cursor-unbound;
`execute()` masked prompt fallback on an fzf too old for the binds — ADR 0051).
The confirmed value is stored in the **no-SOPS secrets manifest** under
`enc_passphrase` and staged into install-state under `.guided_passwords.*` — the
same key family that does **not** activate the SOPS runtime (ADR 0049). It never
enters Config State and is never written by Save/Export.

One rule diverges from passwords: **first entry must be ≥ 8 chars** (a notice on a
short entry keeps the operator on the screen). ZFS `keyformat=passphrase` hard-
requires 8; enforcing it in the menu turns a mid-install `zpool create` failure
into an inline correction. Password rows keep their non-empty-only rule.

The passphrase joins the **Proceed gate** with full password parity: while
encryption is on and the passphrase is unset, **Proceed blocks**
(`set passwords first ⚠`) and the **Disks** top-category row shows
`⚠ 1 pw needed`. Toggling encryption **off** hides the row and drops the gate but
**retains** any stored passphrase silently — toggling back on shows `(set)` again
(a fat-finger toggle costs nothing).

Back-end consumption is a precedence extension of `collect_enc_passphrase`
(`lib/zfs/pools.sh`): **`INSTALL_ENC_PASSPHRASE`** (test/VM preset) → **guided
manifest** → **interactive tty prompt**. The tty prompt therefore **stays** for
profile/manual installs that have no fzf front end. Timing is already correct —
the guided manifest is written by the front end before `collect_enc_passphrase`
runs (03-install.sh:200), ahead of pool creation.

This **supersedes ADR 0051's carve-out** ("the ZFS encryption passphrase keeps
its back-end prompt"): the prompt is now a fallback, not the only path. The
INSTALL / ACCEPT tty gates are untouched.

## Root shell

A **`root shell`** row lands on the **Users** screen directly under
`root password`: `root shell: bash   (Enter cycles)`, cycling
`/bin/bash` → `/bin/zsh` → `/bin/fish` — the **same cycle** the User Editor uses
for a user shell (`_ctl_cycle_next`). Root stays a flat pair of rows (password,
shell); it does **not** grow a per-user-style Root Editor.

The choice is stored at Config State **`options.root_shell`** (default
`/bin/bash`, normalised out when it equals the default — the standard scalar-field
delta), so it bakes into Export and a saved profile like any other host option.
It has a valid default, so it is **not** gated.

It is applied inside the chroot in **`lib/chroot/password.sh`** (which already
runs `chpasswd` for root): `chsh` root to the chosen shell, and **install the
shell's package if absent** first — the same missing-login-shell guard
`create-user.sh` uses, so a root shell of zsh/fish can never leave root with an
unusable login.

## Considered Options

### Passphrase capture surface
- **Guided inline-masked, back-end prompt as fallback** — chosen. One seam;
  guided and profile/manual installs both keep working, and the entry surface
  matches the passwords the operator just set two rows up.
- **Guided-only, remove the tty prompt** — rejected. Breaks encrypted
  profile/manual installs, which have no fzf to type into.
- **Keep back-end-only** — rejected. That is today's split (secrecy captured in
  two different places) the request set out to unify.

### Passphrase row location
- **Disks, under the encryption toggle** — chosen. Config sits next to the thing
  it configures; the row appears/disappears with the toggle.
- **Users/secrets screen** — rejected. Groups it with the other secrets but
  divorces it from the encryption decision that makes it required.
- **New Security category** — rejected. New nav for a single row.

### Passphrase length rule
- **Enforce min 8 in the menu** — chosen. Matches the ZFS requirement; fails
  fast, inline, before any disk write.
- **Non-empty only (exact password parity)** — rejected. A 1–7 char passphrase
  would pass the menu and blow up at `zpool create`.

### Toggle-off lifecycle
- **Retain silently** — chosen. The passphrase is unused (and un-gated) while
  encryption is off; a stray toggle is free to undo.
- **Clear on toggle-off** — rejected. Cleaner secrecy, but a fat-finger toggle
  silently discards a typed-twice passphrase.

### Root shell UI
- **Inline cycle row on the Users screen** — chosen. Matches root's existing flat
  treatment and the user shell cycle; smallest surface.
- **Root Editor screen** — rejected. Consistent with the per-user editor but a
  larger restructure for root's two settings.

### Root shell storage
- **`options.root_shell` scalar, host-level** — chosen. Root is not a user
  profile; a host option bakes cleanly into Export/profile with the standard
  default-delta behaviour.
- **A `users/root` profile / `root.*` object** — rejected for now. More schema
  than one scalar needs; extensible later if root grows settings.

## Consequences

- The secrets manifest grows an `enc_passphrase` key and
  `guided_secretsfile_*` gain a passphrase accessor family; `collect_enc_
  passphrase` grows a middle precedence tier. Config State grows
  `options.root_shell`.
- The Proceed gate now aggregates two sources — Users (root + per-user passwords)
  **and** Disks (passphrase when encryption is on) — so the "set passwords first"
  block can originate on either screen.
- **VM-verifiable.** Both paths exercise real seams: the manifest→`collect_enc_
  passphrase` handoff drives the actual passphrase-unlock path (via
  `INSTALL_ENC_PASSPHRASE` still available as the non-interactive preset), and
  `options.root_shell` is observable as root's `/etc/passwd` shell post-install.
- Supersedes the passphrase scope note in ADR 0051; the inline-masked surface,
  no-SOPS manifest, and Proceed gate of ADR 0051/0049 are otherwise unchanged.
