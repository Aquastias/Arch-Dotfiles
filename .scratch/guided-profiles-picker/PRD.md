# Guided in-menu Profiles picker + default-`12345` secret posture

Status: done

ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## Problem Statement

I keep two personal machines — a desktop (`eterniox`) and a laptop (`chronos`) —
each with a committed Host Profile. Reinstalling either means remembering the
right `install.sh --profile <name>` invocation from a shell, and then the Guided
Installer (bare `install.sh`) always starts from scratch with no way to say "just
give me my desktop." Worse, even when I do load a profile, the installer *blocks*
Proceed until I type a root password, every user password, and an encryption
passphrase — so "install my known machine" is never a quick, few-keystroke
operation. I want to boot the ISO, pick `desktop` or `laptop` from the menu, and
install, tweaking only if I feel like it.

## Solution

The Guided Installer gains a **Profiles** entry at the top of its menu. Selecting
it lists my installable Host Profiles; picking one **seeds** the whole menu from
that profile, so every category already reflects it and I can Proceed immediately
(disks are still picked interactively — profiles never carry device paths).

Secrets stop being a gate. Root, every user, and the encryption passphrase
**default to `12345`**; nothing blocks Proceed. A single Users screen lists every
account plus `Disk encryption`, each tagged with its current source
(`default 12345` / `custom` / `from age`), so overriding any one is a keystroke
away but never required. If an age key resolves, my committed encrypted secrets
decrypt and take precedence over the default automatically.

The two personal profiles are re-cut to their real shape: encrypted, impermanent,
SSH-enabled ZFS machines. The net result: boot ISO → `Profiles ▸ desktop` →
Proceed → pick disks → type `INSTALL` → done.

## User Stories

1. As an operator, I want a `Profiles` row at the top of the guided menu, so that
   selecting a known machine is the first thing I see.
2. As an operator, I want `Profiles` visually separated above the category
   divider, so that it reads as a distinct action, not another config category.
3. As an operator, I want selecting `Profiles` to drill into a dedicated screen,
   so that I know I am now choosing a profile.
4. As an operator, I want the Profiles screen to list every installable Host
   Profile, so that I can pick any machine I have committed.
5. As an operator, I want `core` excluded from the list, so that I am never
   offered the merge base as an installable machine.
6. As an operator, I want the `vm/` tree excluded from the list, so that harness
   fixtures never clutter my interactive choices.
7. As an operator, I want the profiles listed alphabetically, so that the order
   is predictable as I add machines.
8. As an operator, I want each profile's `//` header comment shown in a preview
   pane, so that I can read what a profile installs before picking it.
9. As an operator, I want a profile with no/thin header to show a dim
   `(no description — hosts/<name>/profile.jsonc)` hint, so that I am told where
   to look rather than facing an empty pane.
10. As an operator, I want `Esc` on the Profiles screen to return to the top
    menu, so that browsing profiles is non-committal.
11. As an operator, I want picking a profile to seed the whole menu from that
    profile's values, so that every category reflects the machine I chose.
12. As an operator, I want to tweak any seeded value before installing, so that a
    profile is a starting point, not a straitjacket.
13. As an operator, I want to Proceed immediately after picking a profile, so
    that an unmodified profile installs with no further configuration.
14. As an operator, I want disks still picked interactively at Proceed, so that a
    profile stays portable and never wipes the wrong machine's disk.
15. As an operator, I want the `Profiles` row hidden when no installable profile
    exists, so that a fresh repo's guided menu behaves exactly as before.
16. As an operator, I want root, every user, and the encryption passphrase to
    default to `12345`, so that I can install a known machine without typing any
    secret.
17. As an operator, I want Proceed to never be blocked on a missing password or
    passphrase, so that "install now" is always available.
18. As an operator, I want a Users screen listing root, each user, and
    `Disk encryption`, so that there is one place to review and change secrets.
19. As an operator, I want each secret tagged `default 12345` / `custom` /
    `from age`, so that I can see at a glance whether a secret is still the
    default before I install.
20. As an operator, I want to override any single secret with an inline masked
    prompt, so that I can harden one account or the disk passphrase without
    touching the others.
21. As an operator, I want a resolvable age key to decrypt my committed secrets
    and take precedence over the default, so that my real passwords are used
    when the key is present.
22. As an operator without an age key, I want the `12345` default to apply
    silently, so that the encrypted path is optional, never mandatory.
23. As an operator, I want the `12345` default to never be written to Config
    State, Save, or Export, so that no profile ever commits a password.
24. As an operator, I want the `WILL ERASE` review and typed-`INSTALL`
    confirmation to always run, so that a one-select install can still never
    wipe a disk silently.
25. As an operator, I want the `desktop` profile to install encrypted ZFS with a
    `rpool` mirror (2 disks) plus a `data` raidz1 (3 disks), so that it matches my
    real desktop hardware.
26. As an operator, I want the `laptop` profile to install encrypted single-disk
    ZFS, so that it matches my real laptop.
27. As an operator, I want both profiles impermanent, so that each boots from a
    clean root with only declared state persisted.
28. As an operator, I want `/home`, `/var/lib/docker`, and `/var/lib/libvirt`
    persisted on both machines, so that my data, containers, and VMs survive the
    impermanent rollback.
29. As an operator, I want SSH enabled on both machines, so that I can reach them
    remotely right after install.
30. As an operator, I want both profiles to state `filesystem: "zfs"` explicitly,
    so that the filesystem is on the profile's face, not an inherited default.
31. As an operator authoring off-target, I want the Profiles picker and secret
    override screen to work with no disks present, so that I can prepare an
    install from any machine.
32. As a maintainer, I want a future `hosts/<name>` profile to appear in the
    picker automatically, so that the list needs no per-profile wiring.

## Implementation Decisions

- **Profile enumeration (new pure helper).** A pure function takes the `hosts/`
  root and returns the installable profiles — directories containing a
  `profile.jsonc`, **excluding `core`** (the merge base) and the **`vm/` tree**
  (harness fixtures, ADR 0035) — as names plus the leading `//` header-comment
  block for each (empty when absent). Alphabetical. No TTY, no fzf.
- **Profile seed-merge (new pure helper).** A pure function merges a parsed
  profile delta over the seeded launch Config State using the same jq `*` deep
  merge as `cfgstate_seed_defaults` / the guided effective-state read, yielding
  the Config State the rest of the menu renders. Disks/device paths are not part
  of the seed — the profile is device-less (ADR 0036) and resolution stays at
  Proceed.
- **Profiles category in the menu model.** The Menu model surfaces a `Profiles`
  entry as the first top-screen row, above the terminal/category divider. It
  drills to a values-style screen whose options are the enumerated profiles;
  selecting one applies the seed-merge and returns to the top screen. When
  enumeration is empty the entry is omitted from the model.
- **Preview pane.** The Profiles screen shows the selected profile's header
  comment; a missing/thin comment renders the dim
  `(no description — hosts/<name>/profile.jsonc)` fallback. Reuses the existing
  guided preview-window mechanism.
- **Default-`12345` secret posture (global).** Root, per-user passwords, and the
  encryption passphrase default to `12345`. The Proceed gate no longer blocks on
  any secret: the existing "required-but-unset" signals become **display-only
  precedence tags**, not blockers. Precedence per secret: age-decrypted committed
  secret (ADR 0025, via `options.age_key_url` / local `/etc/secrets` key) →
  operator override → `12345`.
- **Secrets manifest defaulting.** The no-SOPS secrets manifest builder fills any
  unset secret with `12345` before install-state staging, so the back-end always
  receives a concrete value. The `12345` default is runtime-only and never enters
  Config State, Save, or Export (the secret-free-state invariant of ADR
  0042/0051 is unchanged).
- **Users screen as the override surface.** The Users screen lists root, each
  user, and a `Disk encryption` entry, each tagged `default 12345` / `custom` /
  `from age`. Enter opens the existing inline-masked secret screen (ADR 0051).
  Override scope is passwords + passphrase only; SSH identities stay on their
  current per-user/age path.
- **Consent unchanged.** The `WILL ERASE` review and typed-`INSTALL` gate run on
  every Proceed regardless of how secrets were sourced.
- **`install.sh` wiring.** The bare-invocation path (no `--profile`, no positional
  config, no `--guided`) is unchanged in trigger — it still opens the guided menu;
  the Profiles picker lives inside that menu. `--profile`, positional config, and
  `--guided` headless paths are untouched.
- **Personal profile content.** `hosts/desktop/profile.jsonc` and
  `hosts/laptop/profile.jsonc` are updated: explicit `filesystem: "zfs"`;
  `options.encryption` on; `options.impermanence.enabled` on;
  `options.ssh.enabled` on; `persist.directories` = `/home`, `/var/lib/docker`,
  `/var/lib/libvirt` (additive over the `impermanence-common.sh` base set). The
  existing layouts already match (desktop `mode: multi`, `rpool` mirror ×2 +
  `data` raidz1 ×3; laptop `mode: single`) and are unchanged. Each edited profile
  must still load clean against the closed schema (ADR 0036).

## Testing Decisions

- **Test external behavior only** — the JSON/text a pure helper emits and the menu
  rows the model produces are the contract, never internal structure. This mirrors
  the header discipline in `guided-menu.bats` ("the rows ARE the contract") and
  `guided-seed.bats`.
- **Profile enumeration** — bats over a **fixture `hosts/` tree**: asserts
  `desktop`/`laptop` appear, `core` and anything under `vm/` do not, ordering is
  alphabetical, and the header-comment text is returned (with the empty-header
  fixture yielding the fallback signal). Prior art: `guided-seed.bats`,
  `guided-skeleton.bats`.
- **Profile seed-merge** — bats: a parsed profile delta over a seeded state yields
  a Config State whose fields equal the profile's values, with untouched fields
  retaining the seed. Prior art: `guided-state.bats`, `guided-seed.bats`.
- **Secret posture (menu model)** — bats over `menu.sh`/controller: a state with
  no secrets set produces secret rows tagged `default 12345` and **no**
  Proceed-block signal; an overridden secret tags `custom`; an age-resolved secret
  tags `from age`. Prior art: `guided-menu.bats`, `guided-shell.bats`.
- **Secret posture (manifest)** — bats over the no-SOPS manifest builder: unset
  secrets emit `12345`; set/age-resolved secrets emit their value; nothing secret
  appears in the emitted Config State / Save / Export. Prior art:
  `guided-secrets.bats`.
- **Personal profiles load** — bats/config-load assertion that the edited
  `desktop`/`laptop` profiles parse and validate against the closed schema with
  encryption/impermanence/ssh on and the persist set present. Prior art:
  existing profile-load / validation tests.
- **fzf Profiles screen + `install.sh` wiring** — **smoke-only**, matching the
  rest of the guided fzf shell (`tools/guided-fzf-smoke.py`, `guided-fzf-entry`
  coverage). No new TTY-driven unit tests.

## Out of Scope

- **Committing device paths / baked disks in profiles.** Disks stay
  operator-picked; ADR 0036's device-less invariant is not reversed.
- **Committing plaintext passwords in a profile.** The `12345` default is runtime
  only; the encrypted (age/SOPS) path remains the sole committed-secret mechanism.
- **A pre-menu launcher screen.** Profile selection lives inside the guided menu,
  not as a separate front-end before it (ADR 0055 rejected the launcher).
- **Focus-dimming sibling menu rows.** Infeasible in the single persistent fzf;
  the drill-to-screen provides the "you are here" cue instead.
- **New in-menu age-key entry UI.** Age keys resolve via the existing
  `options.age_key_url` / `/etc/secrets` mechanism only.
- **SSH identity keys in the override screen.** Only passwords + the encryption
  passphrase are editable there; SSH identities keep their current path.
- **New behavior for `--profile`, positional-config, or `--guided` headless
  paths.** Only the interactive bare-`install.sh` menu changes.
- **Adding persist paths beyond `/home` + docker + libvirt**, or `/var/log`.

## Further Notes

- ADR 0055 supersedes ADR 0039's rejected option (c) (require-a-profile) and the
  ADR 0051/0054 Proceed password/passphrase gate. Read it alongside this PRD.
- **Recorded security trade-off:** a Proceed with no overrides installs every
  account and the disk passphrase as `12345`. This is accepted for personal
  hardware and bounded by the always-on `INSTALL` consent gate and the
  one-keystroke override screen.
- The impermanence base set (`lib/impermanence-common.sh`) already persists
  `/etc/ssh`, machine-id, secrets, NetworkManager connections, and LUKS/zfs
  keyfiles, so SSH host keys and network state survive rollback without being
  listed in the profiles.
- Both personal profiles install `docker` and `virt-manager`, which is why
  `/var/lib/docker` and `/var/lib/libvirt` are persisted on both, not just the
  desktop.
