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

**Status:** ready-for-agent

- [ ] `runner_resolve_post_install <pi_json> <any_zfs> [uprog...]`
- [ ] bats: ext4 variant with backup on does not select zfs-auto-snapshot
- [ ] bats: gate any-ZFS parity with `install_config_any_zfs`

## Comments
