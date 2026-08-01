# Guided in-menu encryption passphrase + root shell

Status: done

Ref: ADR 0054 (supersedes the passphrase carve-out in ADR 0051)

## Problem Statement

Two gaps in the Guided Installer, both around credentials/identity the operator
sets before install:

1. **The encryption passphrase is captured in a different place from every other
   secret.** Root and per-user passwords are typed inline in the menu (masked,
   confirmed, stored in the no-SOPS Secrets Manifest — ADR 0051). But the ZFS/LUKS
   passphrase is *not* in the menu at all: the operator sails through the whole
   guided session, hits Proceed, and only *then* gets an out-of-band tty prompt
   mid-install. It is the one secret the menu doesn't own, and there is nothing on
   screen telling the operator it will be required.

2. **Root's login shell can't be chosen.** Every user gets a `shell` row in the
   User Editor (bash/zsh/fish). Root is stuck on Arch's default `/bin/bash` with
   no control anywhere — even though the operator is right there setting root's
   password two rows up.

## Solution

1. Add an **Encryption Password Row** to the Disks screen, directly under the
   `encryption` toggle (shown only when encryption is on). It captures the
   passphrase the *same inline-masked way* as the password rows and joins the
   Proceed gate, so the requirement is visible up front and typed in one place.
   The back-end tty prompt stays as a fallback for profile/manual installs.

2. Add a **Root Shell** row to the Users screen under `root password`, cycling
   bash/zsh/fish exactly like the user shell cycle, applied to root at install.

Both reuse the existing guided credential/user machinery — no new subsystems.

## User Stories

1. As an operator building an encrypted host, I want to type the encryption
   passphrase in the guided menu, so that every secret is set in one place.
2. As an operator, I want the passphrase entry to be masked as bullets, so that
   my passphrase is never shown on screen.
3. As an operator, I want to confirm the passphrase by typing it twice, so that a
   typo can't lock me out of a machine I can't boot.
4. As an operator, I want the passphrase row to appear only when encryption is
   on, so that the menu doesn't ask for something the install won't use.
5. As an operator, I want the row to read `(not set)` / `(set)` (never the
   value), so that I can see its state at a glance like the password rows.
6. As an operator, I want a clear warning when encryption is on but the
   passphrase is unset, so that I know I have to set it before installing.
7. As an operator, I want Proceed blocked while a required passphrase is unset,
   so that I can't start an install that will stall on a prompt or fail.
8. As an operator, I want the Disks category row to show `⚠ 1 pw needed` when the
   passphrase is missing, so that I see the gap before drilling into Disks.
9. As an operator, I want a too-short passphrase rejected inline with a notice,
   so that I don't discover the 8-char minimum only when `zpool create` fails
   mid-install.
10. As an operator who toggles encryption off, I want the passphrase row and its
    warning to disappear, so that the menu reflects that no passphrase is needed.
11. As an operator who toggles encryption off then on again, I want my
    already-typed passphrase retained, so that a stray toggle doesn't cost me the
    entry.
12. As an operator on an older fzf, I want the passphrase entry to fall back to
    the out-and-back masked prompt, so that the feature degrades instead of
    breaking (parity with password entry).
13. As an operator, I want the passphrase kept out of any saved profile or
    exported config, so that sharing a config never leaks the passphrase.
14. As an operator doing a profile or manual (non-guided) install, I want the
    back-end passphrase prompt to still work, so that non-guided encrypted
    installs are unaffected.
15. As a test/CI author, I want a preset passphrase env override to still win
    over the guided value, so that non-interactive VM runs stay deterministic.
16. As an operator whose guided install captured a passphrase, I want the
    encrypted pool created with exactly that passphrase, so that the machine
    unlocks at first boot with what I typed.
17. As an operator, I want to choose root's login shell in the guided menu, so
    that root gets my preferred shell without a manual post-install `chsh`.
18. As an operator, I want the root shell row to cycle bash/zsh/fish on Enter,
    so that it behaves like the user shell control I already know.
19. As an operator, I want root's shell to default to bash, so that leaving it
    alone matches today's behavior.
20. As an operator, I want my root shell choice baked into an exported config /
    saved profile, so that re-installing reproduces it.
21. As an operator who picks zsh or fish for root, I want that shell's package
    installed automatically, so that root login can't break on a missing shell.
22. As an operator, I want root's shell set to my choice in the installed system,
    so that logging in as root drops me into the shell I selected.
23. As an operator, I want the root shell control to require no password/gate, so
    that a valid default never blocks Proceed.

## Implementation Decisions

### Encryption passphrase — front-end (guided controller)

- A new `encryption password` row renders on the **Disks** screen immediately
  after the `encryption` toggle, **only when encryption is on**. State shows via
  the existing `_ctl_secret_state`-style `(set)` / `(not set)` (with `⚠` when
  unset), never the value.
- Enter on the row opens the **existing inline-masked secret screen** used by the
  password rows: a new secret **target `enc`** alongside `root`/`user`, routed
  through the same `nav_to_secret` / secret render / `_ctl_enter_secret` flow
  (type-twice confirm, masked bullets, cursor-unbound). On an fzf too old for the
  masking binds, degrade to the ADR 0049 `execute()` masked prompt via the same
  rich-chrome gate the password rows use.
- **Min length 8** is enforced on the *first* entry only (the ZFS
  `keyformat=passphrase` minimum): a shorter entry emits a `notice` and stays on
  the entry screen. This is the single deliberate divergence from password rows
  (which reject only empty).
- **Proceed gate:** the passphrase counts as a required secret while encryption
  is on and unset. Proceed emits the blocked directive, and the Disks
  top-category row shows `⚠ 1 pw needed`. The gate now aggregates two origins —
  Users (root + per-user passwords) and Disks (passphrase) — so the block can
  come from either screen.
- **Toggle-off lifecycle:** turning encryption off hides the row and drops it
  from the gate but **does not clear** the stored passphrase; turning it back on
  shows `(set)` again.

### Encryption passphrase — storage (Secrets Manifest / injector)

- The confirmed value is written to the no-SOPS **Secrets Manifest** under a new
  `enc_passphrase` key and staged by the guided injector into install-state under
  the `.guided_passwords.*` family (the key family that does **not** activate the
  SOPS runtime). It never enters Config State and is never emitted by Save/Export.
- The manifest/injector interface gains a passphrase accessor family paralleling
  the existing root/user password accessors (has / set / read).

### Encryption passphrase — back-end (`collect_enc_passphrase`)

- `collect_enc_passphrase` resolves `ZFS_PASSPHRASE` by precedence:
  `INSTALL_ENC_PASSPHRASE` (test/VM preset) → **guided manifest value** →
  interactive tty prompt. The tty prompt is retained as the fallback for
  profile/manual installs. Timing is already correct: the guided manifest is
  written by the front end before `collect_enc_passphrase` runs, ahead of pool
  creation, so no reordering of the install flow is required.

### Root shell — front-end

- A new `root shell: <name>   (Enter cycles)` row renders on the **Users** screen
  directly under `root password`. Enter cycles `/bin/bash` → `/bin/zsh` →
  `/bin/fish` using the same cycle helper the User Editor's shell row uses.
- The choice writes Config State **`options.root_shell`** (default `/bin/bash`),
  normalised out when it equals the default (standard scalar-field delta) so it
  bakes into Export and a saved profile. Not gated.

### Root shell — back-end (chroot)

- `lib/chroot/password.sh` (which already applies root's password) additionally
  sets root's login shell to the resolved `options.root_shell` via `chsh`, and
  **installs the shell's package first if absent**, reusing the missing-login-
  shell guard pattern from `create-user.sh`. The resolved value crosses into the
  chroot the same way `ROOT_PW` does (host-side resolution, one value in).

## Testing Decisions

Good tests here assert **external behavior at a seam**, not internals: the
controller through its rendered list + `(directive, file-mutation)` pairs (it runs
entirely off state files, no fzf/tty); the injector through the files it writes +
the install-state seam; the chroot module through the system state it produces.

- **Guided controller** (`tests/config/guided-controller.bats`, existing):
  - Disks list shows the `encryption password` row only when encryption is on,
    reads `(not set)`/`(set)`, and carries the `⚠`.
  - Enter on the row navigates to the `enc` secret screen; a `< 8` first entry
    emits a notice and stays; a valid type-twice writes the manifest and returns.
  - Proceed is blocked and the Disks top row shows `⚠ 1 pw needed` while
    encryption is on and the passphrase is unset; toggling encryption off clears
    the gate but retains the stored value.
  - Users list shows `root shell: <name>`; Enter cycles bash→zsh→fish and writes
    `options.root_shell`, normalising the value out when it lands on the default.
- **Guided secrets injector** (`tests/config/guided-secrets.bats`, existing): an
  `enc_passphrase` in the manifest lands as its decrypted file + the
  `.guided_passwords.*` seam, with `.secrets.*` untouched (no SOPS activation) —
  mirroring the existing root/user password tracer tests.
- **Back-end resolution** (`collect_enc_passphrase`, prior art
  `tests/secrets.bats`): precedence `INSTALL_ENC_PASSPHRASE` → guided manifest →
  prompt yields the right `ZFS_PASSPHRASE`; the prompt path still works when
  neither preset is present.
- **Chroot root shell** (`tests/chroot/chroot-password.bats`, existing, already
  covers the root password): root's `/etc/passwd` shell ends up at the resolved
  `options.root_shell`, and a non-default shell triggers the package install
  (guard prior art in `tests/chroot/chroot-create-user.bats`).
- **VM integration** (`arch-zfs-test-guided-secure`, existing guided+encryption
  run): the guided→manifest→`collect_enc_passphrase` handoff drives the real
  passphrase-unlock path via the `INSTALL_ENC_PASSPHRASE` preset, and
  `options.root_shell` is observable as root's shell in the booted system.

## Out of Scope

- A per-user-style **Root Editor** screen — root stays a flat pair of rows
  (password, shell). Only the shell is added.
- Any **root settings beyond the shell** (groups, dotfiles, etc.).
- Changing the **password rows'** non-empty-only rule (they do not gain a minimum
  length; only the passphrase enforces 8).
- The **INSTALL / ACCEPT** tty confirmation gates — untouched.
- **SOPS / encrypted-secrets** flows — the passphrase uses the no-SOPS manifest,
  same as the existing guided passwords.
- Per-pool distinct passphrases — the single shared-passphrase seam (ADR 0040)
  is unchanged; one passphrase still applies to all encrypted pools.

## Further Notes

- This supersedes ADR 0051's explicit carve-out ("the ZFS encryption passphrase
  keeps its back-end prompt"); that note is now marked superseded, and the
  back-end prompt is a fallback rather than the sole path. See ADR 0054.
- Glossary terms added in CONTEXT.md: **Encryption Password Row**, **Root Shell**.
- Wording: the on-screen row says "encryption password" (operator-facing), while
  code/docs use "passphrase" (the ZFS term) — intentional, per the grilling
  session.
