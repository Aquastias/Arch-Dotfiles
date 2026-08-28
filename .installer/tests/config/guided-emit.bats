#!/usr/bin/env bats
# Tests for .installer/lib/config/emit.sh — the Guided Installer's Emitter (ADR
# 0039):
# an effective view (+ optional disk assignment) → a device-baked Effective
# Config. Pure: JSON-in/JSON-out, no TTY, no disk writes.
#
# Host Core enters ONCE, via the menu baseline (cfgstate_seed_defaults), so
# these build their state the way guided.sh does: overrides over a seeded
# baseline. The emitter merging core a second time is exactly the bug where
# the menu showed `grub` and the install produced `["cups","grub"]`.
#
# Behaviour under test (external only — the effective config the emitter
# produces), never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # Host Core declares a plain System Program (grub) — cups is no longer a core
  # program but the toggle-derived one injected at emit (ADR 0079), so these
  # exercise both: an authored core program AND the printing-derived cups.
  mkdir -p "$INSTALLER_DIR/hosts/core"
  printf '%s\n' \
    '{"host_programs":["grub"],"sysctl":{"vm.swappiness":10}}' \
    > "$INSTALLER_DIR/hosts/core/profile.jsonc"

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/seed.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/seed.sh"
  # shellcheck source=../../lib/config/emit.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  # validate_config_schema — assert the guided output is schema-clean.
  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# effective <state> — overrides over the seeded (Host Core) baseline, the same
# shape guided.sh passes to emit_effective.
effective() {
  jq -n --argjson b "$(cfgstate_seed_defaults "$(cfgstate_new)")" \
        --argjson o "$1" '$b * $o'
}

# ── tracer: single-disk ZFS Effective Config over Host Core ─────────────────

@test "emit_effective: bakes hostname + picked disk merged over Host Core" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" mode '"single"')"
  # Isolate the printing-derived cups: disable the other toggle-derived System
  # Programs (bluetooth, power — ADR 0080) so host_programs stays focused.
  state="$(cfgstate_set "$state" options.bluetooth.enabled 'false')"
  state="$(cfgstate_set "$state" options.power.profile '"none"')"
  assignment='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  run emit_effective "$(effective "$state")" "$assignment"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
  echo "$output" | jq -e '.mode == "single"'
  echo "$output" | jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"'
  # Host Core still applies (grub authored); printing (on by default) injects
  # cups and the Mirrors section always injects reflector (ADR 0089).
  echo "$output" | jq -e '.host_programs == ["grub","cups","reflector"]'
  echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
}

# ── Options + Environment overrides ride through to the Effective Config ────

@test "emit_effective: Options + Environment overrides bake in, schema-clean" {
  state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"
  state="$(cfgstate_set "$state" options.kernel '["zen","lts"]')"
  state="$(cfgstate_set "$state" options.bootloader '"grub"')"
  state="$(cfgstate_set "$state" options.swap 'false')"
  state="$(cfgstate_set "$state" options.swap_size '"8G"')"
  state="$(cfgstate_set "$state" options.esp_size '"4G"')"
  state="$(cfgstate_set "$state" options.ssh.enabled 'true')"
  state="$(cfgstate_set "$state" options.age_key_url '"https://x.test/k.age"')"
  state="$(cfgstate_set "$state" environment.desktop '["kde"]')"
  state="$(cfgstate_set "$state" environment.gpu '["amd","nvidia"]')"
  assignment='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  run emit_effective "$(effective "$state")" "$assignment"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.options.kernel == ["zen","lts"]'
  echo "$output" | jq -e '.options.bootloader == "grub"'
  echo "$output" | jq -e '.options.swap == false'
  echo "$output" | jq -e '.options.swap_size == "8G"'
  echo "$output" | jq -e '.options.ssh.enabled == true'
  echo "$output" | jq -e '.environment.desktop == ["kde"]'
  echo "$output" | jq -e '.environment.gpu == ["amd","nvidia"]'

  # the guided output stays as schema-clean as a hand-authored profile.
  run validate_config_schema host "$(emit_effective "$state" "$assignment")"
  [ "$status" -eq 0 ]
}

# ── the emitter does NOT promote: a name is a Program or a package ──────────
# Promotion used to run here and only here, so the guided path and the two
# profile/config paths disagreed about the same file. The emitter now passes
# packages through untouched; routing happens at entry, exclusivity at load.

@test "emit_effective: a package name is passed through, never promoted" {
  mkdir -p "$INSTALLER_DIR/programs/security/wireguard"
  printf '{"name":"wireguard","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/security/wireguard/config.jsonc"
  : > "$INSTALLER_DIR/programs/security/wireguard/install.sh"

  state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"
  state="$(cfgstate_set "$state" packages.repo.extra '["htop"]')"
  assignment='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  run emit_effective "$(effective "$state")" "$assignment"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.packages.repo.extra == ["htop"]'
  echo "$output" | jq -e '.host_programs | index("grub")'   # core kept
  echo "$output" | jq -e '.host_programs | index("cups")'   # printing-derived
  echo "$output" | jq -e '.host_programs | index("htop") | not'
}

# ── the menu and the installer produce the same set (ADR 0058) ──────────────
# The original report was "profile system programs do not appear selected".
# The root cause was the inverse: profile programs mark fine; CORE programs
# were invisible, and the merge under-reported. Both halves are asserted here.

# cups is toggle-derived (ADR 0079), so it is NOT a baseline system program —
# the Printing toggle rides the baseline instead (on by default). cups is
# materialised only at emit, mirroring GPU/audio/security derived sets.
@test "the print daemon is toggle-derived, not a baseline System Program" {
  local base; base="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  jq -e '.host_programs | index("cups") | not' <<<"$base"
  jq -e '.options.printing.enabled == true' <<<"$base"
}

@test "printing on injects cups at emit; off omits it" {
  local state; state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"
  # Isolate printing from the other toggle-derived programs (ADR 0080).
  state="$(cfgstate_set "$state" options.bluetooth.enabled 'false')"
  state="$(cfgstate_set "$state" options.power.profile '"none"')"
  local asgn='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  # default on → cups injected alongside the authored core program; reflector is
  # always injected by Mirrors (ADR 0089)
  run emit_effective "$(effective "$state")" "$asgn"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.host_programs == ["grub","cups","reflector"]'

  # turned off → cups absent, the authored core program untouched; reflector
  # still lands (state-independent)
  local off; off="$(cfgstate_set "$state" options.printing.enabled 'false')"
  run emit_effective "$(effective "$off")" "$asgn"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.host_programs == ["grub","reflector"]'
}

@test "menu view and installed set agree, aside from the derived cups" {
  local state; state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"
  # Isolate printing from the other toggle-derived programs (ADR 0080).
  state="$(cfgstate_set "$state" options.bluetooth.enabled 'false')"
  state="$(cfgstate_set "$state" options.power.profile '"none"')"
  state="$(cfgstate_set "$state" packages.repo.extra '["htop"]')"
  local view; view="$(effective "$state")"

  run emit_effective "$view" \
    '{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'
  [ "$status" -eq 0 ]
  # packages/sysctl survive the emit unchanged (disks aside); the only
  # host_programs differences are the section-derived cups (printing) and
  # reflector (mirrors) the emit injects.
  local shown installed
  shown="$(jq -cS '{packages, sysctl}' <<<"$view")"
  installed="$(jq -cS '{packages, sysctl}' <<<"$output")"
  [ "$shown" = "$installed" ]
  local shown_sp installed_sp
  shown_sp="$(jq -cS '.host_programs' <<<"$view")"
  installed_sp="$(jq -cS \
    '(.host_programs - ["cups","reflector"])' <<<"$output")"
  [ "$shown_sp" = "$installed_sp" ]
}

# Deselecting a core-inherited entry must actually deselect it — the old emit
# concatenated core back in, so unticking silently did nothing. cups is exempt
# (toggle-owned, injected regardless), so this untick uses the authored core
# program grub: unticking it removes grub, while the derived cups still lands.
@test "unticking a core system program removes it from the install" {
  local state; state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"
  # Isolate printing from the other toggle-derived programs (ADR 0080).
  state="$(cfgstate_set "$state" options.bluetooth.enabled 'false')"
  state="$(cfgstate_set "$state" options.power.profile '"none"')"
  state="$(cfgstate_set "$state" host_programs '[]')"

  run emit_effective "$(effective "$state")" \
    '{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.host_programs | index("grub") | not'
  echo "$output" | jq -e '.host_programs == ["cups","reflector"]'
}

# ── Save writes a DELTA over Host Core, not a snapshot (ADR 0056) ───────────
# The baseline now legitimately contains core's whole package list, so a save
# that wrote the effective view verbatim would bake it in and decouple the new
# profile from core on the next edit.

@test "guided_core_delta: drops what Host Core already provides" {
  local core='{"host_programs":["cups"],"sysctl":{"vm.swappiness":10},
               "packages":{"repo":{"shell":["htop","fzf"]}}}'
  local eff='{"host_programs":["cups","grub"],
              "sysctl":{"vm.swappiness":10},
              "packages":{"repo":{"shell":["htop","fzf","btop"]}},
              "system":{"hostname":"eterniox"}}'
  run guided_core_delta "$eff" "$core"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.host_programs == ["grub"]'
  echo "$output" | jq -e '.packages.repo.shell == ["btop"]'
  echo "$output" | jq -e 'has("sysctl") | not'
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

@test "guided_core_delta: a replace key equal to core's is dropped" {
  run guided_core_delta '{"options":{"kernel":["lts"],"bootloader":"grub"}}' \
                        '{"options":{"kernel":["lts"]}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.options | has("kernel")) | not'
  echo "$output" | jq -e '.options.bootloader == "grub"'
}

@test "guided_core_delta: a replace key differing from core's is kept whole" {
  run guided_core_delta '{"options":{"kernel":["zen"]}}' \
                        '{"options":{"kernel":["lts"]}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.options.kernel == ["zen"]'
}

# The contract that makes "stays layered" true: resolving the saved delta back
# over Host Core must reproduce exactly what the operator saw.
@test "guided_core_delta round-trips through the Layer Resolver" {
  source "$BATS_TEST_DIRNAME/../../lib/config/layer-resolver.sh"
  local core='{"host_programs":["cups"],"sysctl":{"vm.swappiness":10},
               "packages":{"repo":{"shell":["htop","fzf"]}}}'
  local eff='{"host_programs":["cups","grub"],
              "sysctl":{"vm.swappiness":10},
              "packages":{"repo":{"shell":["htop","fzf","btop"]}},
              "options":{"kernel":["zen"]}}'
  local delta round
  delta="$(guided_core_delta "$eff" "$core")"
  round="$(layer_resolve host "$core" "$delta")"
  [ "$(jq -cS . <<<"$round")" = "$(jq -cS . <<<"$eff")" ]
}

@test "Save writes a delta: core's packages are not baked into the profile" {
  # a richer core than the setup default, to make the snapshot obvious
  cat > "$INSTALLER_DIR/hosts/core/profile.jsonc" <<'JSON'
{"host_programs":["cups"],"sysctl":{"vm.swappiness":10},
 "packages":{"repo":{"shell":["htop","fzf","btop"]}}}
JSON
  source "$BATS_TEST_DIRNAME/../../lib/guided-save.sh"

  local state; state="$(cfgstate_set "$(cfgstate_new)" mode '"single"')"
  state="$(cfgstate_set "$state" system.hostname '"newbox"')"
  run guided_save_host_profile "$(effective "$state")" newbox
  [ "$status" -eq 0 ]

  local saved; saved="$(cat "$INSTALLER_DIR/hosts/newbox/profile.jsonc")"
  # core's inherited payload is absent from the committed delta …
  jq -e '(.packages // {}) == {}'          <<<"$saved"
  jq -e 'has("host_programs") | not'     <<<"$saved"
  jq -e 'has("sysctl") | not'              <<<"$saved"
  # … but the operator's own choices are there
  jq -e '.system.hostname == "newbox"'     <<<"$saved"
  jq -e '.mode == "single"'                <<<"$saved"
}

# ── safety: the guided output is as schema-clean as a hand-authored profile ─

@test "emit_effective: the produced config passes closed-schema validation" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" mode '"single"')"
  assignment='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  effective="$(emit_effective "$state" "$assignment")"
  run validate_config_schema host "$effective"
  [ "$status" -eq 0 ]
}
