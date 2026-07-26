# Guided in-menu Profiles picker + default-`12345` secret posture

---
Status: accepted
---

The Guided Installer gains an in-menu **Profiles** picker that **seeds** the menu
from a committed Host Profile, and its secret handling flips from a **mandatory
Proceed gate** to a **default-`12345`, override-if-you-want** posture across root,
per-user passwords, and the encryption passphrase. Together these make a personal
machine a one-select install: pick `desktop`/`laptop`, Proceed, pick disk(s).

## Profiles picker (in-menu seed)

A **`Profiles ▸`** row lands **first on the top screen, above the category
divider** — visually separated from the Configuration Categories. Enter drills to
a dedicated **Profiles screen** listing the installable Host Profiles
(`hosts/*/profile.jsonc` **minus `core`** — the merge base — and **minus the
`vm/` tree** — harness fixtures, ADR 0035), alphabetical, with the profile's
`//` header comment shown in the preview pane (a missing/thin header falls back to
a dim `(no description — hosts/<name>/profile.jsonc)`). `Esc` returns to the top.

Picking a profile **seeds** the Config State: the profile's delta is merged over
the Host Core baseline, so every category now reflects that profile's values,
which the operator may then tweak or Proceed on. Disks are **not** seeded — the
profile is device-less (ADR 0036) and the operator picks physical disks at
Proceed exactly as before. When no installable profile exists the `Profiles` row
is hidden and the menu behaves as it does today.

This **supersedes ADR 0039's rejected option (c)** ("require loading a profile
first"). 0039 rejected *requiring* a profile and kept guided a from-scratch
on-ramp; it did not anticipate an *optional* in-menu seed. Guided's contract is
now "from scratch **or** from a profile," selected per-run. The 0039 boundary that
still holds: guided remains the un-audited on-ramp, and Save is still the bridge
back to a committed profile.

## Default-`12345` secret posture

Root, every user, and the encryption passphrase **default to `12345`** and
**Proceed is no longer gated** on any of them. This replaces the
"`set passwords first ⚠`" block (ADR 0051/0054) and the `_ctl_pw_missing` /
`_ctl_enc_missing` gate signals. Precedence per secret:

1. **age-decrypted** committed secret (existing SOPS/age path, ADR 0025) when a
   key resolves via `options.age_key_url` or a local `/etc/secrets` key — shown
   `🔒 from age`.
2. **operator override** typed in the menu — shown `custom`.
3. **`12345`** default — shown `default 12345`.

The **Users screen** is the single override surface: it lists root · each user ·
**`Disk encryption`**, each tagged with its precedence state; Enter opens the
existing inline-masked secret screen (ADR 0051). Overriding is one keystroke away
but never required. The encryption passphrase joins this model rather than keeping
its own gate — a `12345` passphrase is weak by design of the opt-in, and the same
screen is where it is hardened.

This is a **global** posture change (every guided install, not only
profile-seeded ones) and it **supersedes the Proceed password/passphrase gate of
ADR 0051/0054**. It aligns interactive guided with the `--unattended` root-default
already in `install.sh`. The `12345` default is only ever a *runtime* default — it
never enters Config State, Save, or Export (the secret-free-state invariant of
ADR 0042/0051 is unchanged), so no profile ever commits a password.

## What does **not** change

- **Disks stay operator-picked.** ADR 0036's device-less profile invariant is
  **not** reversed — no by-id device path is ever committed to `hosts/`.
- **The consent gate stands.** The `WILL ERASE` review + typed-`INSTALL`
  confirmation runs on every Proceed, so a one-select install can still never
  wipe a disk silently. This is the guard the `12345` default leans on.

## Considered Options

### Where profile selection lives
- **In-menu `Profiles` category that seeds, drill-to-screen** — chosen. Sits
  beside Proceed as one coherent flow; reuses the screen-nav model; no pre-menu
  launcher to maintain.
- **Pre-menu launcher screen** — rejected. A second selection surface before the
  menu, and a profile picked there can't be tweaked without re-deriving the seed.
- **Focus-dimming the rest of the menu while hovering `Profiles`** — rejected as
  infeasible: the single persistent fzf (ADR 0042) can only highlight the current
  line, not restyle siblings on focus. The drill-to-screen delivers the same "you
  are now picking a profile" cue via the breadcrumb.

### Secret posture
- **Default `12345`, no gate, optional override, age-decrypt precedence** —
  chosen. The only model that yields a true one-select install while keeping
  secrets out of committed source.
- **Keep the mandatory Proceed gate** — rejected. It is exactly the friction that
  blocks "select and run" for a personal machine.
- **Commit plaintext passwords in the profile** — rejected outright. A plaintext
  credential in a synced/forked/backed-up dotfiles repo is the failure mode every
  prior secret ADR avoids.

### Encryption passphrase
- **Joins the `12345` model** — chosen. One posture for every secret; the
  override screen is where a strong passphrase is set.
- **Stays gated while account passwords default** — rejected. Splits the model and
  breaks one-select on any encrypted profile (which both personal profiles are).

## Consequences

- The Proceed gate loses its password/passphrase blocking; `_ctl_pw_missing` /
  `_ctl_enc_missing` become display-only precedence tags, not blockers. The
  no-SOPS manifest defaults any unset secret to `12345` before install-state
  staging.
- Guided grows a pure profile **enumerator** and a **seed-merge** step (profile
  delta over Host Core into Config State), both bats-tested; the fzf Profiles
  screen is smoke-only, matching the rest of the guided shell.
- The `desktop` and `laptop` Host Profiles are re-cut as encrypted, impermanent,
  SSH-enabled ZFS machines (explicit `filesystem: "zfs"`;
  `options.encryption`/`impermanence.enabled`/`ssh.enabled` on; persist `/home`
  `/var/lib/docker` `/var/lib/libvirt` over the `impermanence-common.sh` base
  set) — the concrete personal profiles this feature exists to one-select.
- **Security note, recorded deliberately:** a Proceed with no overrides installs
  every account and the disk passphrase as `12345`. This is an accepted trade-off
  for personal hardware, bounded by the always-on `INSTALL` consent gate and the
  one-keystroke override screen.
