# 01 — `disk_config` kind + manual layout planner (pure core)

**What to build:** The pure foundation for Manual Partitioning. Disk
configuration gains a discriminated `disk_config.kind` — `auto` (today's pool
skeleton, the default when the kind is absent, so every existing config is
untouched) vs `manual` (a flat `partitions[]` list). A new pure
planner/validator takes a `partitions[]` assignment and emits a validated
format+mount plan, or a clear, actionable error. No disk access, no UI — feeding
an assignment in yields a plan (or a named rejection) out.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `disk_config.kind` joins the closed host schema; absent kind resolves to
      `auto`; `manual` is accepted. Unknown keys still abort with their path.
- [ ] `partitions[]` joins the schema, each entry `{ device, mountpoint, fs,
      format }`; `mountpoint` accepts `/`, `/boot/efi`, `/home`, `[swap]`, or
      empty/none; `fs` accepts ext4/xfs/btrfs/fat32; `format` is boolean.
- [ ] Accessors: `install_config_disk_kind` (auto default) and
      `install_config_partition_*` (count, device, mountpoint, fs, format).
- [ ] A pure planner/validator turns `partitions[]` into a format+mount plan
      (what is `mkfs`'d, what is mounted where, what is `mkswap`'d).
- [ ] Validation rejects: no root, no ESP, ESP not FAT32, duplicate `/`; each
      error names the offending condition.
- [ ] Partitions with no mountpoint are omitted from the plan (ignored).
- [ ] Headless bats covers the plan cases and every rejection, modelled on
      `tests/layout/nonzfs-plan.bats`. The `auto` path is unchanged.
