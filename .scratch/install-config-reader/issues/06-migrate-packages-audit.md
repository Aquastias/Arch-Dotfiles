# 06: Move packages and feature-audit onto the reader

**What to build:** the package libs and the Feature Audit (~37 reads) read
the Effective Config only through the Install Config Reader — bound to
JSON where the module holds JSON — with no raw `// <default>` jq reads of
config paths. Behaviour unchanged. Fields missing from the schema get a row
here. The raw-read lint baseline shrinks by every migrated read. Decisions:
candidate #1, Q17 (expand–contract batch).

**Blocked by:** 01, 03

**Status:** done

- [x] No raw config reads left in this scope
- [x] Lint baseline entries for this scope removed
- [x] Scope's existing tests green; full suite green

## Comments

2026-10-15: Package Resolver (gpu ×2, kernels, bootloader, filesystems,
display manager) and its desktop sets (stock ×2, wayland shell) read bound
accessors; kernels via `install_config_get kernels` (report, no validation
abort). `_package_resolver_filesystems` takes disk kind + root filesystem
from the reader; group filesystems stay explicit-only jq. Feature Audit
host side (bind gate, boot2 impermanence via `install_config_get`, session
client) binds the reader; gate.sh / live-phases.sh source it at file level.
probe-lib.sh is staged into the guest (no installer reader there): its two
restated defaults are `raw-config-ok` — follow-up idea: the host stages
FA_CONFIG with the Install Defaults filled in. Edge: gpu `[]` now reads as
auto (as install does). packages + feature-audit suites green.

2026-10-15 (code review), unrecorded behaviour edge: a root `filesystem: ""`
now resolves to zfs in `_package_resolver_filesystems` (old jq emitted `""`)
— matches install. kde audit.sh uses `feature_audit_stock`; the lint now
scans extras/ and programs/. zswap.sh (chroot, Install State) keeps its
fallback — no reader in the chroot; recorded in ADR 0154. New test: a
manual layout reports no LUKS set even with encryption on.
