#!/usr/bin/env bats
# Tests for the Guided Installer's always-on master-detail pane (ADR 0071;
# top-screen parent column dropped by ADR 0082): guided_ctl_preview shows the
# highlighted item's live detail. The category screen still renders a
# sibling-field parent column (current marked) above the leaf; the top screen
# shows only the highlighted category (current selection is the fzf triangle
# pointer in the main list). The render is pure — driven entirely by the state +
# nav files, no fzf, no tty — asserted through the body, never internal structure.

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

# ── top screen: the highlighted category's field summary only (ADR 0082) ────
# The parent-column preview is gone — the current selection is the fzf triangle
# pointer in the main list, so the pane shows just the highlighted category.

@test "detail(top): a category previews only its own fields, no parent column" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "System — hostname, timezone, fonts"
  [ "$status" -eq 0 ]
  # the highlighted category's own fields show
  echo "$output" | plain | grep -qE 'hostname:'
  # ...but sibling categories are NOT listed (parent column removed)
  ! echo "$output" | plain | grep -q "Locales"
  ! echo "$output" | plain | grep -q "Mirrors & Repositories"
}

@test "detail(top): a category previews its fields as key: value" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "System — hostname, timezone, fonts"
  [ "$status" -eq 0 ]
  echo "$output" | plain | grep -qE 'timezone: +Europe/Bucharest'
}

@test "detail(top): an overridden field carries a ● in the summary" {
  printf '%s\n' '{"system":{"hostname":"myhost"}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "System — hostname, timezone, fonts"
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

@test "detail(top): a non-category row (Proceed) previews nothing" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "Proceed ▸ review & install"
  [ "$status" -eq 0 ]
  # no parent column and no bogus "Proceed" field summary (ADR 0082)
  ! echo "$output" | plain | grep -q "Locales"
  ! echo "$output" | plain | grep -qE 'hostname:|Proceed:'
}

@test "detail(top): a bucket header previews nothing" {
  set_nav '{"screen":"top"}'
  run guided_ctl_preview "── GENERAL ──"
  [ "$status" -eq 0 ]
  ! echo "$output" | plain | grep -qE 'hostname:|Locales'
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
  set_nav "$(nav_to_text System system.hostname hostname)"
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
  ! echo "$output" | plain | grep -qE '▶ +(kernel|System)'
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
