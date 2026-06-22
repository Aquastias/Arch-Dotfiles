# Security & Backup Extras back-end

Status: done

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Make `post_install.security` / `post_install.backup` real, structured
**Security & Backup Extras** installed via the Primary User's paru pass
(ADR 0041), independent of the guided menu UI (drive it via a committed
Host Profile + VM smoke).

Schema migration (bool → object): `post_install.security` =
`{ firewall: "firewalld"|"ufw"|"none", antivirus: bool, rootkit: bool,
apparmor: bool }`; `post_install.backup` =
`{ zfs_auto_snapshot: bool, borg: bool }`. Update the closed schema, the
schema-table accessors, and the Menu field table; the back-end default stays
**absent = off**.

Resolver (M2): a pure core mapping a `post_install.{security,backup}` object
to the ordered Program-name list (firewall choice → firewalld / ufw /
neither, clamav, rkhunter, apparmor, zfs-auto-snapshot, borg), plus the
secure-baseline default object and shape validation.

Runner (M4): union the resolved Program names into `users[0]`'s paru pass
(the seam host AUR already uses) and dedup against that user's own `programs`
so a tool in both installs once. The selection→install decision is a pure,
unit-tested function; the chroot wiring stays in the Runner. Each tool's
existing Program Install Script runs unchanged in the per-user paru context.

Data: prune `firewalld` / `apparmor` / `clamav` / `rkhunter` from
`users/aquastias/profile.jsonc`; migrate `hosts/vm/arch-secure` and
`hosts/vm/arch-secure-kde-hyprland` from the bool form to the object form;
remove the dead `extras/security.sh` / `extras/backup.sh` dispatch.

## Acceptance criteria

- [x] Closed schema accepts the object form and rejects the old bool form and
      malformed objects (bad firewall enum, non-bool fields).
- [x] Resolver maps every firewall × bool combination to the correct Program
      list; the default object = firewalld + clamav + rkhunter + apparmor +
      zfs-auto-snapshot + borg.
- [x] A tool declared in both `post_install` and `users[0].programs` installs
      once (dedup), order-preserving.
- [x] aquastias's profile no longer lists the 4 security programs; the two
      `arch-secure*` profiles validate under the object schema.
- [x] bats for the resolver and the Runner union+dedup function (prior art
      `tests/config/guided-emit.bats`, `tests/profiles/*`).
- [x] VM smoke: an `arch-secure*` profile installs and the selected daemons
      (firewalld, clamav, rkhunter, apparmor) are enabled in the booted
      system. **DONE 2026-06-22 — see Comments (two KVM smokes).**

## Blocked by

None - can start immediately.

## Comments

**DONE via /tdd (2026-06-21).** Back-end landed; pure cores TDD'd vertically
(resolver → schema → M4), the schema-forced plumbing/data landed in lockstep.
Only the VM smoke (AC6) is deferred — no VM here.

**M2 resolver** (`lib/config/post-install.sh`, new): three pure fns over the
`post_install.{security,backup}` object. `post_install_default` → the secure
baseline (firewalld + antivirus/rootkit/apparmor on; zfs_auto_snapshot + borg
on). `post_install_programs <json>` → the ordered Program names (firewall enum
→ firewalld/ufw/neither; bool toggles → clamav/rkhunter/apparmor/
zfs-auto-snapshot/borg), canonical order, absent/false omitted. Hardened to
coerce a **non-object** security/backup to off (a legacy `true` would index a
boolean and abort the whole runner; `// {}` alone keeps `true` — the jq
`//`-swallows-false trap). `post_install_validate <json>` → rejects the bool
form, a bad firewall enum and non-bool toggles; absent = valid. 12 bats.

**Schema** (`profile.sh`): the two `post_install.{backup,security}` leaf
patterns become the six object sub-paths; `validate_profile` now calls
`post_install_validate` on `.post_install` (the closed schema only guards key
*names*, not the object/bool distinction). +2 bats in `profile-loader.bats`.

**M4 union+dedup** (`runner.sh`): `_profiles_resolve_post_install
<post_install_json> [uprog…]` — resolves the extras and unions them into the
Primary User's install list: the user's own programs first (declared order),
then the resolved extras not already present (canonical order); a tool in both
installs once. Wired into `run_profiles`' `users[0]` pass, so each extra
installs via the existing per-user program path (all seven programs are
`system:false` → reconcile routes them to a per-user paru install; their
Install Scripts run unchanged). 4 bats (`tests/profiles/profiles-post-install.
bats`).

**Plumbing / dead-dispatch removal** (D1): dropped the `extras_backup` /
`extras_security` accessors, the install-state `.extras` block (schema + write),
and the never-shipped `chroot/extras.sh` backup.sh/security.sh dispatch
(`extras.sh` is now just the Environment Runner). `lifecycle.sh`'s summary prints
the resolved Extras program list instead of the two opaque bools. Fixed the
affected tests (`install-state.bats` ← SSH stands in for the nested-bool
coverage; `environment-runner.bats` ← the 2 dispatch tests gone;
`chroot-initcpio.bats` ← stale `.extras` dropped). `03-install.sh` +
`profile.sh` + `lifecycle.sh` + `runner.sh` source the new module.

**Data**: `users/aquastias/profile.jsonc` drops firewalld/apparmor/clamav/
rkhunter (now host-owned post_install). Both `hosts/vm/arch-secure*` migrated
bool → object with the **secure baseline on** (decision: AC6 needs the daemons
enabled to assert on; old bools were inert no-ops). The 15 legacy VM-harness
seeds under `tests/vm/profiles/` keep their `install.post_install` bool form —
not the profile schema, not bats-validated; the resolver's non-object coercion
makes a replay safe.

Full suite **1278 bats, 0 failures; shellcheck clean** (`--severity=warning`).
Menu field table + the guided Security/Backup editors are **issue 05** (the
two bool menu rows stay inert until 05 wires the radiolist/toggles). Unblocks
issue 05.

**VM smoke DONE (2026-06-22, two KVM runs) — AC6 satisfied.** Both via
`git daemon` serving a bare mirror + `REPO_URL` override (no push); both with
`vm-test` as `users[0]` (no user programs, so only the host Extras install via
its paru pass — the M4 union end-to-end).
- `single/guided-extras --verify-boot` (issue 05's harness, unencrypted, so it
  boot-verifies): install `EXIT-0` → **`EXTRAS-OK`** (firewalld + clamav +
  rkhunter + apparmor all `systemctl is-enabled` on the booted system) →
  `FIRSTBOOT-OK`. Backup toggled off in the replay (skips the heavy borg/Vorta).
- `headless/secure` (this issue's `arch-secure` host profile, object-form
  post_install, SOPS + ZFS-encrypted + impermanent 2-disk mirror; install-only
  — an encrypted root can't headless-boot-verify): install **`EXIT-0`**, the
  Runner installed **all six** Extras (firewalld/clamav/rkhunter/apparmor/
  zfs-auto-snapshot/borg) via `vm-test`'s paru pass; `Borg staged`, `SOPS
  runtime staged`, `Profiles runner complete`.
The secure run flushed **two pre-existing, unrelated program-install bugs**
(both fixed, separate commits): `sops/install.sh` built ssh-to-age with no
`HOME`/`GOPATH` in the chroot (`go: module cache not found`); `borg/install.sh`
pinned `python-borgmatic`, which the Arch repos renamed to `borgmatic`. Neither
is issue-04 code — the Extras resolver/Runner drove every tool's install
correctly. Harness additions (committed): `single/guided-extras` profile +
seed-generator `verify_extras`/`guided_extras` seams; the fixture HTTP server
(Test Age Key) ported into the test flow (`_fixture_http_should_serve` +
`_start_fixture_http_server`); `tests/vm/profiles/headless/secure.jsonc`.
