# 05 — End-to-end VM case + declarative-path guardrails

**What to build:** The proof and the fences. A full manual-partitioning VM case
drives the whole path — scripted `cfdisk` seed → assignment → install → verified
boot — so the interactive escape hatch is proven to produce a usable machine. And
the guardrails that keep manual out of the reproducible paths: `kind: manual` is
rejected on the `--profile` Pre-Install Picker and the unattended `install.sh
<config-file>` path, since a hand-drawn table cannot be replayed from a committed
file.

**Blocked by:** 04.

**Status:** ready-for-agent

- [ ] A manual VM matrix case (scripted partition table standing in for the
      operator's `cfdisk`) assigns, installs, and boots; registered on the
      Combination Matrix as a `disk_config.kind: manual` axis value.
- [ ] The `--profile` Pre-Install Picker rejects a config whose
      `disk_config.kind` is `manual`, with an actionable message.
- [ ] The unattended `install.sh <config-file>` path rejects `kind: manual`
      likewise.
- [ ] The rejection guards are covered headless in bats; the boot is verified in
      the VM via the existing harness / `vm/vm-pool-verify.bats` prior art.
