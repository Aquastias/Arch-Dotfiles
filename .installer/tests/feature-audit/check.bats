#!/usr/bin/env bats
# Tests for `feature-audit.sh check` (ADR 0152, feature-audit/04+): the
# Audit Manifest resolves every variant to a valid Effective Config, and
# coverage gaps are Findings. Pure: no VM. Fixture manifests are written per
# test; the real hosts/ tree is the data root.

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TOOL="$INSTALLER_DIR/tools/feature-audit.sh"
  M="$BATS_TEST_TMPDIR/manifest.jsonc"
  export FEATURE_AUDIT_MANIFEST="$M"
  # manifest-only checks; coverage checks opt in per test
  export FEATURE_AUDIT_CHECKS="manifest"
}

# manifest <variants-json> [unverifiable-json]
manifest() {
  jq -n --argjson v "$1" --argjson u "${2:-[]}" '{
    vm_name: "arch-audit",
    base: { host: "arch-audit",
            hardware: { disks: [60, 60, 20], ram_mb: 10240, vcpus: 8 },
            fixtures: ["fixtures/key.age"] },
    variants: $v, unverifiable: $u }' > "$M"
}

cfg() {
  bash -c "source '$INSTALLER_DIR/lib/jsonc.sh'
    source '$INSTALLER_DIR/lib/feature-audit/manifest.sh'
    INSTALLER_DIR='$INSTALLER_DIR' fa_variant_config '$1'"
}

@test "valid manifest: check exits 0" {
  manifest '[{"id":"base"},
    {"id":"limine","patch":{"options":{"bootloader":"limine"}}}]'
  run bash "$TOOL" check
  [ "$status" -eq 0 ]
}

@test "patch reaches the resolved config (bootloader)" {
  manifest '[{"id":"limine","patch":{"options":{"bootloader":"limine"}}}]'
  run cfg limine
  [ "$status" -eq 0 ]
  jq -e '.options.bootloader == "limine"' <<<"$output"
}

@test "patch applies before assembly: derived power daemon follows it" {
  manifest '[{"id":"ppd",
    "patch":{"options":{"power":{"profile":"power-profiles-daemon"}}}}]'
  run cfg ppd
  jq -e '(.host_programs | index("power-profiles-daemon"))
    and (.host_programs | index("tuned") | not)' <<<"$output"
}

@test "real host variant resolves through its own profile" {
  manifest '[{"id":"kde-pure","host":"kde-pure",
    "hardware":{"disks":[40],"ram_mb":6144,"vcpus":4}}]'
  run cfg kde-pure
  [ "$status" -eq 0 ]
  jq -e '.environment.stock == true' <<<"$output"
}

@test "invalid patched config is a Finding naming the variant" {
  manifest '[{"id":"bad","patch":{"options":{"esp_size":"256M"}}}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"variant bad"* ]]
}

@test "unknown real host is a Finding" {
  manifest '[{"id":"ghost","host":"no-such-host",
    "hardware":{"disks":[40],"ram_mb":6144,"vcpus":4}}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"variant ghost"* ]]
}

@test "duplicate variant ids are a Finding" {
  manifest '[{"id":"base"},{"id":"base"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate variant id base"* ]]
}

@test "unverifiable entry without a reason is a Finding" {
  manifest '[{"id":"base"}]' '[{"feature":"program:lact"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"program:lact"* ]]
}

@test "the committed manifest is well-formed and every variant resolves" {
  # Validation failures here are real audit Findings (fixed in the fix
  # session), so only structural problems fail this test.
  unset FEATURE_AUDIT_MANIFEST
  run bash "$TOOL" check
  [[ "$output" != *"does not resolve"* ]]
  [[ "$output" != *"duplicate variant"* ]]
  [[ "$output" != *"has no reason"* ]]
}

# ── feature ↔ variant coverage (feature-audit/06) ────────────────────────────

@test "features: a menu value no variant enables is a Finding" {
  export FEATURE_AUDIT_CHECKS="features"
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"feature options.bootloader=grub"* ]]
  # the base's own values are covered
  [[ "$output" != *"feature options.bootloader=systemd-boot"* ]]
  [[ "$output" != *"feature environment.desktop=niri"* ]]
  # matrix-owned storage axes and identity fields are not features here
  [[ "$output" != *"feature filesystem="* ]]
  [[ "$output" != *"feature system.hostname"* ]]
  [[ "$output" != *"options.pacman"* ]]
}

@test "features: a variant enabling the value covers it" {
  export FEATURE_AUDIT_CHECKS="features"
  manifest '[{"id":"base"},
    {"id":"grub","patch":{"options":{"bootloader":"grub"}}}]'
  run bash "$TOOL" check
  [[ "$output" != *"feature options.bootloader=grub"* ]]
}

@test "features: bool fields need both sides; missing value = menu default" {
  export FEATURE_AUDIT_CHECKS="features"
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [[ "$output" == *"feature options.printing.enabled=false"* ]]
  [[ "$output" != *"feature options.printing.enabled=true"* ]]
}

@test "features: unverifiable entry and guided covers satisfy coverage" {
  export FEATURE_AUDIT_CHECKS="features"
  manifest '[{"id":"base"},{"id":"g","guided":"single/guided-manual",
    "covers":["disk_config.kind=manual"]}]' \
    '[{"feature":"environment.gpu=nvidia","reason":"no GPU in a VM"}]'
  run bash "$TOOL" check
  [[ "$output" != *"feature environment.gpu=nvidia"* ]]
  [[ "$output" != *"feature disk_config.kind=manual"* ]]
  [[ "$output" == *"feature environment.gpu=amd"* ]]
}

# ── program ↔ probe coverage (feature-audit/09) ─────────────────────────────

# fake_programs — a data root with two programs, one probed.
fake_programs() {
  FAKE="$BATS_TEST_TMPDIR/root"
  mkdir -p "$FAKE/programs/system/zsh" "$FAKE/programs/system/lact"
  echo '{"name":"zsh","kind":"user"}' > "$FAKE/programs/system/zsh/config.jsonc"
  echo '{"name":"lact","kind":"host"}' \
    > "$FAKE/programs/system/lact/config.jsonc"
  echo 'fa_pass x y' > "$FAKE/programs/system/zsh/audit.sh"
  export FEATURE_AUDIT_PROGRAMS_DIR="$FAKE/programs"
}

@test "programs: a program without audit.sh is a Finding" {
  export FEATURE_AUDIT_CHECKS="programs"
  fake_programs
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"program lact has no audit probe"* ]]
  [[ "$output" != *"program zsh"* ]]
}

@test "programs: unverifiable program:<name> satisfies coverage" {
  export FEATURE_AUDIT_CHECKS="programs"
  fake_programs
  manifest '[{"id":"base"}]' '[{"feature":"program:lact","reason":"no GPU"}]'
  run bash "$TOOL" check
  [ "$status" -eq 0 ]
}

# ── keybind coverage (feature-audit/11) ──────────────────────────────────────

@test "binds: every shipped bind of a registered source has an expectation" {
  export FEATURE_AUDIT_CHECKS="binds"
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [[ "$output" != *"coverage: niri bind"* ]]
}

@test "binds: a bind with no expectation is a Finding" {
  export FEATURE_AUDIT_CHECKS="binds"
  export FA_REPO_ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FA_REPO_ROOT/.config/niri/conf.d" \
    "$FA_REPO_ROOT/.installer/extras/desktop/niri"
  cp "$BATS_TEST_DIRNAME/fixtures/niri-binds.kdl" \
    "$FA_REPO_ROOT/.config/niri/conf.d/"
  echo '{"expect":[{"action":"quit","effect":"session-ends"}]}' \
    > "$FA_REPO_ROOT/.installer/extras/desktop/niri/audit-binds.jsonc"
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"coverage: niri bind Mod+Return (spawn \"kitty\")"* ]]
  [[ "$output" == *"has no audit expectation"* ]]
  [[ "$output" != *"Mod+Shift+E"* ]]
}

@test "programs: a desktop environment without audit.sh is a Finding" {
  export FEATURE_AUDIT_CHECKS="programs"
  fake_programs
  echo 'fa_pass x y' > "$FAKE/programs/system/lact/audit.sh"
  export FEATURE_AUDIT_EXTRAS_DIR="$FAKE/extras"
  mkdir -p "$FAKE/extras/niri" "$FAKE/extras/kde"
  echo '{}' > "$FAKE/extras/niri/install-niri.jsonc"
  echo '{}' > "$FAKE/extras/kde/install-kde.jsonc"
  echo 'fa_pass x y' > "$FAKE/extras/kde/audit.sh"
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"desktop niri has no audit probe"* ]]
  [[ "$output" != *"desktop kde"* ]]
}

@test "binds: an unparseable expectations file is a Finding" {
  export FEATURE_AUDIT_CHECKS="binds"
  export FA_REPO_ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FA_REPO_ROOT/.config/niri/conf.d" \
    "$FA_REPO_ROOT/.installer/extras/desktop/niri"
  cp "$BATS_TEST_DIRNAME/fixtures/niri-binds.kdl" \
    "$FA_REPO_ROOT/.config/niri/conf.d/"
  printf '{"expect":[{"action":"quit",\n"effect":"sess\nion-ends"}]}\n' \
    > "$FA_REPO_ROOT/.installer/extras/desktop/niri/audit-binds.jsonc"
  manifest '[{"id":"base"}]'
  run bash "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"niri"*"audit-binds.jsonc"*"not valid"* ]]
}
