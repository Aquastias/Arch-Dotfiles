#!/usr/bin/env bats
# Tests for select_changed_targets in tests/select-changed.sh — the pure
# change→test-target resolver behind `run.sh --changed` (ADR 0103). Pure: feed
# it changed paths, assert the emitted target set (or the `--full` sentinel);
# no git, no bats, no filesystem walk. Mirrors profiles-aur.bats's style.

load lib/text-helpers

setup() {
  # shellcheck source=../tests/select-changed.sh
  source "$BATS_TEST_DIRNAME/../tests/select-changed.sh"
}

# A mirrored source subdir resolves to its tests/ subdir token.
@test "a mirrored source dir maps to its tests/ subdir" {
  run select_changed_targets .installer/lib/packages/derivation.sh
  [ "$status" -eq 0 ]
  text_has_line "$output" 'packages'
}

@test "a top-level mirrored dir (extras, vm) maps to its tests/ subdir" {
  run select_changed_targets .installer/extras/desktop/niri/niri.sh
  text_has_line "$output" 'extras'
  run select_changed_targets .installer/vm/lib/domain.sh
  text_has_line "$output" 'vm'
}

# A root/tools script with no mirrored dir maps via the explicit table.
@test "a tools script maps to its root test file(s)" {
  run select_changed_targets .installer/tools/install-pkglist.sh
  text_has_line "$output" 'install-pkglist.bats'
  text_has_line "$output" 'pkglist-profile.bats'
}

@test "a lib root script maps to its root test file" {
  run select_changed_targets .installer/lib/finalize.sh
  text_has_line "$output" 'finalize.bats'
}

@test "02-wipe.sh maps to every wipe test file" {
  run select_changed_targets .installer/02-wipe.sh
  text_has_line "$output" 'wipe-probe.bats'
  text_has_line "$output" 'wipe-select.bats'
}

# A changed test file targets itself (tests/-relative).
@test "a changed test file targets itself" {
  run select_changed_targets .installer/tests/guided/emit.bats
  text_has_line "$output" 'guided/emit.bats'
}

# Broad-Blast Paths widen to --full.
@test "a broad-blast path (common.sh) widens to --full" {
  run select_changed_targets .installer/lib/common.sh
  [ "$output" = "--full" ]
}

@test "a shared fixture change widens to --full" {
  run select_changed_targets .installer/tests/fixtures/hosts/core.jsonc
  [ "$output" = "--full" ]
}

@test "the runner itself widening to --full" {
  run select_changed_targets .installer/tests/run.sh
  [ "$output" = "--full" ]
}

# Any unmapped/unknown path WITHIN .installer/ fails safe to --full.
@test "an unmapped .installer path widens to --full (fail-safe)" {
  run select_changed_targets .installer/some/brand-new/area.sh
  [ "$output" = "--full" ]
}

# Paths outside .installer/ are irrelevant to the suite — ignored, not --full.
@test "a non-.installer path is ignored, not widened to --full" {
  run select_changed_targets .bashrc docs/adr/0103-foo.md .scratch/x/spec.md
  [ "$status" -eq 0 ]
  [ "$output" != "--full" ]
  text_has_line "$output" 'config'   # core-only floor
}

@test "unrelated untracked files alongside a mapped change stay narrow" {
  run select_changed_targets .idea/workspace.xml .mcp.json \
                             .installer/lib/packages/derivation.sh
  [ "$output" != "--full" ]
  text_has_line "$output" 'packages'
}

# One broad-blast/unmapped path in a batch forces --full for the whole run.
@test "a broad-blast path anywhere in the batch forces --full" {
  run select_changed_targets .installer/lib/packages/derivation.sh \
                             .installer/lib/common.sh
  [ "$output" = "--full" ]
}

# A narrow result always unions the Install-Correctness Core.
@test "a narrow result always includes the install-correctness core" {
  run select_changed_targets .installer/lib/packages/derivation.sh
  [ "$output" != "--full" ]
  text_has_line "$output" 'packages'
  text_has_line "$output" 'config'           # core dir
  text_has_line "$output" 'wipe'             # core dir
  text_has_line "$output" 'commons-part-name.bats'  # core FAST_ROOT guard
}

# Empty change still runs the core (no --full, no error).
@test "no changed paths still yields the core, not --full" {
  run select_changed_targets
  [ "$status" -eq 0 ]
  [ "$output" != "--full" ]
  text_has_line "$output" 'config'
}

# Multiple mapped paths union and dedupe.
@test "multiple mapped paths union and dedupe" {
  run select_changed_targets .installer/lib/packages/derivation.sh \
                             .installer/lib/zfs/pools.sh \
                             .installer/lib/packages/package-resolver.sh
  [ "$output" != "--full" ]
  text_has_line "$output" 'packages'
  text_has_line "$output" 'zfs'
  # deduped: exactly one 'packages' line despite two lib/packages changes
  [ "$(printf '%s\n' "$output" | grep -cx 'packages')" -eq 1 ]
}
