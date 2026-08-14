#!/usr/bin/env bats
# Tests for the Guided Installer's always-on master-detail pane (ADR 0071):
# guided_ctl_preview on the top + category screens renders a parent column
# (siblings, current marked) above the highlighted item's live detail. The
# render is pure — driven entirely by the state + nav files, no fzf, no tty —
# so behaviour is asserted through the returned body, never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/userforms.json"
  export OS_DIR="$TEST_DIR"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-userforms.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }
# strip ANSI so assertions test content, not colour codes.
plain() { sed 's/\x1b\[[0-9;]*m//g'; }

# ── top screen: parent column of categories + the category's field summary ──

@test "detail(top): the parent column lists every category, current marked" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "General — hostname, timezone"
  [ "$status" -eq 0 ]
  # every sibling category appears in the parent column
  echo "$output" | plain | grep -q "Locales"
  echo "$output" | plain | grep -q "Mirrors & Repositories"
  echo "$output" | plain | grep -q "Security"
  # the highlighted category is marked with the current-item marker
  echo "$output" | plain | grep -qE '▶ +General'
}

@test "detail(top): a category previews its fields as key: value" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "General — hostname, timezone"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'timezone: +Europe/Bucharest'
}

@test "detail(top): an overridden field carries a ● in the summary" {
  printf '%s\n' '{"system":{"hostname":"myhost"}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "General — hostname, timezone"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'hostname: +myhost.*●'
}

@test "detail(top): Mirrors & Repositories notes the reflector consumer" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "Mirrors & Repositories — countries, multilib"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -q "reflector"
  echo "$output" | plain | grep -q -- "--sort rate"
}

@test "detail(top): a non-category row (Proceed) previews no category detail" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "Proceed ▸ review & install"
  [ "$status" -eq 0 ]
  # still shows the parent column, but no bogus "Proceed" field summary
  echo "$output" | plain | grep -q "Locales"
}

# ── category screen: parent column of sibling fields + the leaf's detail ─────

@test "detail(category): the parent column lists the category's fields, marked" {
  set_nav "$(nav_to_category Kernels)"
  run guided_ctl_preview "Kernel: lts"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE '▶ +kernel'
}

@test "detail(category): a leaf shows its current value and its option set" {
  set_nav "$(nav_to_category Kernels)"
  run guided_ctl_preview "Kernel: lts"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'kernel: +lts'
  # the enumerable field lists its options
  echo "$output" | plain | grep -q "hardened"
  echo "$output" | plain | grep -q "zen"
}

@test "detail(category): the Back row previews the sibling column, no leaf" {
  set_nav "$(nav_to_category Kernels)"
  run guided_ctl_preview "← Back"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'kernel'
}

@test "detail(category): an overridden field carries a ● in the pane" {
  printf '%s\n' '{"options":{"kernel":["zen"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Kernels)"
  run guided_ctl_preview "Kernel: zen"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'kernel.*●'          # parent column + leaf
}

# ── every field screen is populated (ADR 0071): values + text editors ───────

@test "detail(values): a plain enum field screen shows value + options" {
  set_nav "$(nav_to_values Bootloader options.bootloader bootloader)"
  run guided_ctl_preview "[x] systemd-boot"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'bootloader: +systemd-boot'
  echo "$output" | plain | grep -q "grub"                # its option set
}

@test "detail(text): a free-text field screen shows value + a free-text hint" {
  printf '%s\n' '{"system":{"hostname":"eterniox"}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_text General system.hostname hostname)"
  run guided_ctl_preview "eterniox"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'hostname: +eterniox'
  echo "$output" | plain | grep -q "free text"
}

# ── the pane is empty on screens that own their own preview (unchanged) ──────

@test "detail: the datapools screen keeps its live layout graph, not the pane" {
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_preview "single"
  [ "$status" -eq 0 ]
  # no category parent-column header leaks onto the layout screen
  ! echo "$output" | plain | grep -qE '▶ +(kernel|General)'
}

# ── ticket 03: rich leaf detail — Users account table + Disks pool tree ──────

@test "detail(top Users): previews the account table, not a users: field row" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "Users — primary user, extra accounts"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -q "Accounts"
  echo "$output" | plain | grep -qE '^root — '            # the root account row
  ! echo "$output" | plain | grep -qE '^ +users:'         # not the raw field
}

@test "detail(top Users): an enabled user shows its shell/sudo/groups panel" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  guided_userform_set "$GUIDED_USERFORMS_FILE" alice shell '"/bin/fish"'
  guided_userform_set "$GUIDED_USERFORMS_FILE" alice sudo 'true'
  guided_userform_set "$GUIDED_USERFORMS_FILE" alice groups '["wheel"]'
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "Users — primary user, extra accounts"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -q "alice"
  echo "$output" | plain | grep -qE 'shell: +/bin/fish'
  echo "$output" | plain | grep -qE 'sudo: +on'
  echo "$output" | plain | grep -qE 'groups: +wheel'
}

@test "detail(category Disks): the Layout row previews the ZFS pool tree" {
  printf '%s\n' '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},
    "data_pools":[{"name":"tank9","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_preview "Layout: custom"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -q "tank9"                 # reused layout graph
}
