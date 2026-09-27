# 05 — End-to-end VM case + declarative-path guardrails

**What to build:** The proof and the fences. A full manual-partitioning VM case
drives the whole path — scripted `cfdisk` seed → assignment → install → verified
boot — so the interactive escape hatch is proven to produce a usable machine. And
the guardrails that keep manual out of the reproducible paths: `kind: manual` is
rejected on the `--profile` Pre-Install Picker and the unattended `install.sh
<config-file>` path, since a hand-drawn table cannot be replayed from a committed
file.

**Blocked by:** 04.

**Status:** done

- [x] A manual VM matrix case (scripted partition table standing in for the
      operator's `cfdisk`) assigns, installs, and boots; registered on the
      Combination Matrix as a `disk_config.kind: manual` axis value.
- [x] The `--profile` Pre-Install Picker rejects a config whose
      `disk_config.kind` is `manual`, with an actionable message.
- [x] The unattended `install.sh <config-file>` path rejects `kind: manual`
      likewise.
- [x] The rejection guards are covered headless in bats; the boot is verified in
      the VM via the existing harness / `vm/vm-pool-verify.bats` prior art.

## Comments

- 2026-09-27 doc sync: shipped in aac47b6, 9a41d8f, c16f2e8, 962cab1, efa5b5a,
  62b6315, c485ed0, 742f4e8, f2c2216 (ADR 0073).
