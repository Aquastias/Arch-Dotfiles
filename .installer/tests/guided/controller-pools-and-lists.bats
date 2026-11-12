#!/usr/bin/env bats
# Tests: pools, swap and big lists (split from controller.bats;
# shared setup in controller-helpers.bash)

load ../lib/json-helpers
load controller-helpers


# ── data-pools editor: multiple pools (tank0/tank1), topology, disk count ─────

@test "list(category Disks): no separate data pools row (it lives under layout)" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  ! echo "$output" | grep -q "data pools:"
}

@test "enter(values __layout__): data-pools opens the editor with a starter pool" {
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run guided_controller_enter "data-pools"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].name == "tank0"'
  file_satisfies "$GUIDED_STATE_FILE" '.mode == "multi"'
}

@test "enter(values __layout__): re-entering data-pools adds no second pool" {
  printf '%s\n' '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run guided_controller_enter "data-pools"
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  file_satisfies "$GUIDED_STATE_FILE" '(.data_pools | length) == 1'
}

@test "enter(datapools): + Add appends tank0 (single-disk stripe ×1) and forces multi" {
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_enter "+ Add data pool"
  [ "$output" = "refresh" ]
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].name == "tank0"'
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].topology == "stripe"'
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].disk_count == 1'
  file_satisfies "$GUIDED_STATE_FILE" '.mode == "multi"'
  file_satisfies "$GUIDED_STATE_FILE" '(.os_pool.pool_name | length) > 0'
}

@test "enter(datapools): a second Add auto-names it tank1" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_enter "+ Add data pool"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[1].name == "tank1"'
}

@test "list(datapools): lists each pool as name: topology ×n" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_list
  echo "$output" | grep -q "tank0: raidz1 ×3"
  echo "$output" | grep -q "+ Add data pool"
}

@test "enter(datapools): selecting a pool opens its editor by index" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2},{"name":"tank1","topology":"stripe","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_enter "tank1: stripe ×1"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" index)" = "1" ]
}

@test "enter(pooledit): topology cycles off stripe, disks cycle, remove deletes" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","topology":"stripe","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "topology: stripe   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].topology == "mirror"'
  run guided_controller_enter "disks: 2   (Enter cycles 1-8)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].disk_count == 3'
  run guided_controller_enter "✗ remove this pool"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools == []'
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

# issue 09: the topology cycle follows the pool's own filesystem — a btrfs group
# cycles single/raid0/raid1/raid10, never the zfs mirror/raidz set.
@test "enter(pooledit): a btrfs pool cycles the btrfs topology set" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"btrfs","topology":"single","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "topology: single   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].topology == "raid0"'
}

@test "enter(pooledit): an ext4 pool topology stays single (single-disk only)" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"ext4","topology":"single","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "topology: single   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].topology == "single"'
}

# issue 09: the pool editor authors a per-group filesystem + encryption.
@test "enter(pooledit): the filesystem row cycles the pool's filesystem" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"zfs","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "filesystem: zfs   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].filesystem == "btrfs"'
}

@test "enter(pooledit): cycling a group to ext4 pins it single-disk" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"btrfs","topology":"raid1","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "filesystem: btrfs   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].filesystem == "ext4"'
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].topology == "single"'
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].disk_count == 1'
}

@test "enter(pooledit): the encryption row toggles the pool's encryption" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"zfs","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "encryption: false   (Enter toggles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].encryption == true'
  run guided_controller_enter "encryption: true   (Enter toggles)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].encryption == false'
}

@test "enter(pooledit): an ext4 pool's disk count stays pinned at 1" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"ext4","topology":"single","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_enter "disks: 1   (Enter cycles 1-8)"
  file_satisfies "$GUIDED_STATE_FILE" '.data_pools[0].disk_count == 1'
}

@test "list(pooledit): shows the filesystem and encryption rows" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"btrfs","topology":"raid1","disk_count":2,"encryption":true}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_list
  echo "$output" | grep -q "filesystem: btrfs"
  echo "$output" | grep -q "encryption: true"
}


# ── swap: one Disks row → swapedit sub-editor (enabled + free-text size) ──────

@test "list(category Disks): one swap row, no separate swap size row" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  [ "$(echo "$output" | grep -cE '^Swap:')" = "1" ]
  ! echo "$output" | grep -qE '^Swap size:'
}

@test "list(category Disks): swap row defaults to size + zswap, no dot" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^Swap: auto · zswap zstd$'   # default on + zswap
}

@test "enter(category): swap opens the swapedit sub-editor" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_enter "Swap: auto"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "swapedit" ]
}

@test "list(swapedit): default shows enabled on + size auto + Back" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^enabled: on$'
  echo "$output" | grep -qE '^size: auto$'
  echo "$output" | grep -q "← Back"
}

@test "enter(swapedit): toggling enabled flips options.swap and STAYS (refresh)" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "enabled: on"
  [ "$output" = "refresh" ]
  file_satisfies "$GUIDED_STATE_FILE" '.options.swap == false'
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "swapedit" ]
}

@test "enter(swapedit): an explicit swap:false toggles back to true (jq // guard)" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "enabled: off"
  file_satisfies "$GUIDED_STATE_FILE" '.options.swap == true'
}

@test "list(swapedit): swap off hides the size row" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^enabled: off$'
  ! echo "$output" | grep -qE '^size:'
}

@test "enter(swapedit): size opens the text editor; saving returns to swapedit" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "size: auto"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.swap_size" ]
  run guided_controller_enter "" "8G"                 # text screen: query is the value
  file_satisfies "$GUIDED_STATE_FILE" '.options.swap_size == "8G"'
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "swapedit" ]
}

@test "enter(swapedit): Back returns to the Disks category" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "swap label: off / size · zswap <comp> / size · no zswap" {
  run _controller_swap_label '{"options":{"swap":false}}'
  [ "$output" = "off" ]
  run _controller_swap_label '{"options":{"swap_size":"8G"}}'        # zswap default on
  [ "$output" = "8G · zswap zstd" ]
  run _controller_swap_label '{}'
  [ "$output" = "auto · zswap zstd" ]
  run _controller_swap_label '{"options":{"zswap":{"enabled":false}}}'
  [ "$output" = "auto · no zswap" ]
  run _controller_swap_label '{"options":{"zswap":{"compressor":"lz4"}}}'
  [ "$output" = "auto · zswap lz4" ]
}

@test "encryption label: off / on · <tag> (ADR 0059)" {
  run _controller_encryption_label '{"options":{"encryption":false}}' "default 12345678"
  [ "$output" = "off" ]
  run _controller_encryption_label '{}' "default 12345678"        # default off
  [ "$output" = "off" ]
  run _controller_encryption_label '{"options":{"encryption":true}}' "default 12345678"
  [ "$output" = "on · default 12345678" ]
  run _controller_encryption_label '{"options":{"encryption":true}}' "custom"
  [ "$output" = "on · custom" ]
  run _controller_encryption_label '{"options":{"encryption":true}}' "from age"
  [ "$output" = "on · from age" ]
}

@test "list(category Disks): swap row shows a dot once overridden" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^Swap: off  ●$'
}


# ── swapedit: zswap toggle + compressor / max-pool-% cycles (default on) ──────

@test "list(swapedit): default shows the zswap rows (on, zstd, 20)" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^zswap: on$'
  echo "$output" | grep -qE '^compressor: zstd'
  echo "$output" | grep -qE '^max pool %: 20'
}

@test "list(swapedit): zswap off hides compressor + max pool %" {
  printf '%s\n' '{"options":{"zswap":{"enabled":false}}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^zswap: off$'
  ! echo "$output" | grep -qE '^compressor:'
  ! echo "$output" | grep -qE '^max pool %:'
}

@test "list(swapedit): swap off hides every zswap row" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_list
  ! echo "$output" | grep -qE '^zswap:'
  ! echo "$output" | grep -qE '^compressor:'
}

@test "enter(swapedit): toggling zswap flips options.zswap.enabled (refresh)" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "zswap: on"
  [ "$output" = "refresh" ]
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.enabled == false'
}

@test "enter(swapedit): an explicit zswap:false toggles back to true (jq guard)" {
  printf '%s\n' '{"options":{"zswap":{"enabled":false}}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "zswap: off"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.enabled == true'
}

@test "enter(swapedit): compressor cycles zstd → lz4 → lzo → zstd" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "compressor: zstd   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.compressor == "lz4"'
  run guided_controller_enter "compressor: lz4   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.compressor == "lzo"'
  run guided_controller_enter "compressor: lzo   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.compressor == "zstd"'
}

@test "enter(swapedit): max pool % cycles 20 → 40 → 60 → 5" {
  set_navigation "$(navigation_to_swap_edit Disks)"
  run guided_controller_enter "max pool %: 20   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.max_pool_percent == 40'
  run guided_controller_enter "max pool %: 40   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.max_pool_percent == 60'
  run guided_controller_enter "max pool %: 60   (Enter cycles)"
  file_satisfies "$GUIDED_STATE_FILE" '.options.zswap.max_pool_percent == 5'
}


# ── keymap / locale / timezone: big filterable lists + a "selected" side panel ─

@test "enter(category): keymap opens a big filterable list (values screen)" {
  set_navigation "$(navigation_to_category Locales)"
  run guided_controller_enter "Keyboard: us"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "system.keymap" ]
}

@test "list(values keymap): a long MARKED list (multi) that includes us" {
  set_navigation "$(navigation_to_values Locales system.keymap keymap)"
  run guided_controller_list
  [ "${#lines[@]}" -gt 10 ]
  echo "$output" | grep -qE '\] us$'   # marked toggle row "[x]/[ ] us"
}

@test "enter(values keymap): toggling adds a keymap to the array (multi)" {
  printf '%s\n' '{"system":{"keymap":["us"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales system.keymap keymap)"
  run guided_controller_enter "[ ] de"
  [ "$output" = "refresh" ]
  file_satisfies "$GUIDED_STATE_FILE" '.system.keymap == ["us","de"]'
}

@test "list(values timezone): includes region/city entries" {
  set_navigation "$(navigation_to_values System system.timezone timezone)"
  run guided_controller_list
  echo "$output" | grep -qE '^[A-Z][A-Za-z_]+/'
}

@test "list(values language): includes en_US (locale projection, ADR 0076)" {
  set_navigation "$(navigation_to_values Locales __language__ language)"
  run guided_controller_list
  echo "$output" | grep -qx "en_US"
}

@test "enter(values language): picking recomposes system.locale, keeps encoding" {
  printf '%s\n' '{"system":{"locale":"en_US.UTF-8"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales __language__ language)"
  run guided_controller_enter "de_DE"
  [ "$output" = "render" ]
  file_satisfies "$GUIDED_STATE_FILE" '.system.locale == "de_DE.UTF-8"'
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "list(values encoding): filtered to the language's charsets (en_US)" {
  printf '%s\n' '{"system":{"locale":"en_US.UTF-8"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales __encoding__ encoding)"
  run guided_controller_list
  echo "$output" | grep -qx "UTF-8"
  echo "$output" | grep -qx "ISO-8859-1"
}

@test "enter(values encoding): picking recomposes system.locale, keeps language" {
  printf '%s\n' '{"system":{"locale":"de_DE.UTF-8"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales __encoding__ encoding)"
  run guided_controller_enter "ISO-8859-1"
  [ "$output" = "render" ]
  file_satisfies "$GUIDED_STATE_FILE" '.system.locale == "de_DE.ISO-8859-1"'
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "enter(values language): array locale keeps its tail (element 0 edited)" {
  printf '%s\n' '{"system":{"locale":["en_US.UTF-8","fr_FR.UTF-8"]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales __language__ language)"
  run guided_controller_enter "de_DE"
  file_satisfies "$GUIDED_STATE_FILE" \
    '.system.locale == ["de_DE.UTF-8","fr_FR.UTF-8"]'
}

@test "list(values console font): includes the always-present default8x16" {
  set_navigation "$(navigation_to_values Locales system.console_font "console font")"
  run guided_controller_list
  echo "$output" | grep -qx "default8x16"
}

@test "enter(values console font): an installed font sets system.console_font" {
  set_navigation "$(navigation_to_values Locales system.console_font "console font")"
  run guided_controller_enter "default8x16"
  [ "$output" = "render" ]
  file_satisfies "$GUIDED_STATE_FILE" '.system.console_font == "default8x16"'
}

@test "enter(values console font): an off-list font is rejected (no change)" {
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales system.console_font "console font")"
  run guided_controller_enter "no-such-font-xyz"
  [ "$output" = "noop" ]
  file_satisfies "$GUIDED_STATE_FILE" '(.system.console_font // "unset") == "unset"'
}

@test "preview(keymap): the side panel lists the selected keymaps" {
  printf '%s\n' '{"system":{"keymap":["us","de"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Locales system.keymap keymap)"
  run guided_controller_preview "[ ] fr"
  echo "$output" | grep -q "Selected keymaps"
  echo "$output" | grep -q "us"      # a current selection
  echo "$output" | grep -q "fr"      # highlighted candidate (mark stripped)
}

@test "directive→action(render): a keymap screen shows the preview pane" {
  set_navigation "$(navigation_to_values Locales system.keymap keymap)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(right,45%)"
}
