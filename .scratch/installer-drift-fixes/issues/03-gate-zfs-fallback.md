# 03: Feature Audit Probe Gate selects zfs-auto-snapshot on non-ZFS variants

**What to build:** `feature_audit_selected_programs`
(`lib/feature-audit/gate.sh`) calls `runner_resolve_post_install`, which
defaults `_zfs=true` when `install_config_any_zfs` is not loaded — it never
is host-side. So an ext4/xfs/btrfs variant with backup on selects
zfs-auto-snapshot and its probe runs against a program never installed
(confirmed: ext4 config → `zfs-auto-snapshot`).

- Make any-ZFS a required arg of `runner_resolve_post_install` (no silent
  default); the runner passes `install_config_any_zfs`.
- The gate derives any-ZFS from the config JSON (jq); parity test against
  `install_config_any_zfs` on shared fixtures.

Out of scope: the gate also omits secrets-activated `sops` (ADR 0025).
Activation reads install-state `.secrets`, which the gate does not have, and
no audit variant carries secrets today. Deferred to architecture review
candidate #4 (one Program Selection step).

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `runner_resolve_post_install <pi_json> <any_zfs> [uprog...]`
- [x] bats: ext4 variant with backup on does not select zfs-auto-snapshot
- [x] bats: gate any-ZFS parity with `install_config_any_zfs`

## Comments

2026-10-13: `runner_resolve_post_install` requires `<any_zfs>` (errors on a
missing/non-bool value); the runner passes `install_config_any_zfs`, the gate
`feature_audit_any_zfs` (jq). tests/feature-audit/probe-lib.bats: ext4 +
backup selects borg, not zfs-auto-snapshot; 6-fixture parity vs
`install_config_any_zfs`. tests/profiles/profiles-post-install.bats updated +
missing-arg case. Red → green; full suite 3610/3610; readability, shellcheck
(touched files), no-python clean. sops gap remains for candidate #4.
