# 02: Audit + matrix validation pick the Root Layout Adapter ignoring kind

**What to build:** `feature_audit_validate_config`
(`lib/feature-audit/manifest.sh`) and the Tier-1 helper
`_matrix_validate_cell` (`tests/matrix/matrix-assembly.bats`) source
`root_adapter_source <fs> <mode>`. `03-install.sh` uses
`root_adapter_for_kind` (ADR 0073), so a `disk_config.kind=manual` config is
validated against the zfs/ext4 adapter instead of the manual one: a manual
config with no root partition passes the audit `check`. Oversight: the audit
copy (2026-09-29) postdates the kind-aware dispatch (2026-08-09). Latent —
no audit variant or matrix cell is manual today.

Switch both copies to `root_adapter_for_kind`. Merging the three copies into
one validate entry point is architecture review candidate #3.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Both copies dispatch on `install_config_disk_kind`
- [x] bats: audit validation rejects a manual config with no root

## Comments

2026-10-13: Both copies now use `root_adapter_for_kind`.
tests/feature-audit/check.bats: manual variant with no root fails validation
("Manual layout is not installable") — red before (zfs adapter passed it),
green after; check.bats + matrix-assembly.bats green; readability.sh clean.
