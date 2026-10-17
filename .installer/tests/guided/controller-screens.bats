#!/usr/bin/env bats
# Tests: top, category and toggle screens (split from controller.bats;
# shared setup in controller-helpers.bash)

load controller-helpers


# ── top screen ───────────────────────────────────────────────────────────────

@test "list(top): the categories, a divider, and the terminal rows" {
  run guided_controller_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "System — "
  echo "$output" | grep -q "Users — "
  echo "$output" | grep -q "Proceed ▸"
  echo "$output" | grep -q "Save profile ▸"
  echo "$output" | grep -q "Export config ▸"
  echo "$output" | grep -q "Abort ▸"
  echo "$output" | grep -q "──────"
}

@test "list(top): bucket headers group the categories (ADR 0081)" {
  run guided_controller_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "── GENERAL ──"
  echo "$output" | grep -Fq "── SERVICES ──"
}

@test "enter(top): a bucket header is inert (noop)" {
  [ "$(guided_controller_enter "── GENERAL ──")" = "noop" ]
}

# ADR 0083: the focus-skip predicate — decorative rows are inert (the cursor
# hops past them), real rows are selectable.
@test "guided_row_inert: dividers, headers and spacers are inert" {
  run guided_row_inert "── GENERAL ──"                 ; [ "$status" -eq 0 ]
  run guided_row_inert "──────────────────────────"   ; [ "$status" -eq 0 ]
  run guided_row_inert ""                              ; [ "$status" -eq 0 ]
  run guided_row_inert "   "                           ; [ "$status" -eq 0 ]
}

@test "guided_row_inert: categories and actions are selectable" {
  run guided_row_inert "System — hostname, timezone, fonts"; [ "$status" -eq 1 ]
  run guided_row_inert "Services — printing, bluetooth, power"; [ "$status" -eq 1 ]
  run guided_row_inert "Profiles ▸ start from a saved machine"; [ "$status" -eq 1 ]
  run guided_row_inert "Proceed ▸ review & install"    ; [ "$status" -eq 1 ]
  run guided_row_inert "Abort ▸ quit without installing"; [ "$status" -eq 1 ]
}

@test "enter(top): Abort emits the abort directive (Esc-equivalent, ADR 0077)" {
  [ "$(guided_controller_enter "Abort ▸ quit without installing")" = "abort" ]
}

@test "enter(top): a category drills in (render + nav)" {
  run guided_controller_enter "Disks — layout, data pools, filesystem, encryption, swap"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "enter(top): Proceed / Save / Export emit terminal directives" {
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Save profile ▸ x")" = "terminal save" ]
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Export config ▸ x")" = "terminal export" ]
}

@test "enter(top): the divider is inert (noop)" {
  run guided_controller_enter "──────────────────────────"
  [ "$output" = "noop" ]
}


# ── category screen ──────────────────────────────────────────────────────────

@test "list(category Disks): field rows + Disk layout action + Back" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -q "Filesystem: ZFS"
  echo "$output" | grep -qx "Encryption ▸ off"   # collapsed row (ADR 0059)
  echo "$output" | grep -q "Layout: single"   # reflects the default
  echo "$output" | grep -q "← Back"
}

@test "list(category Disks): pinned esp_size too small for kernels warns live" {
  printf '%s\n' '{"filesystem":"zfs","options":{"esp_size":"1G",
    "bootloader":"systemd-boot","kernel":["lts","default","hardened","zen"]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -q "⚠ ESP too small"
}

@test "list(category Kernels): the live ESP warning also shows here (ADR 0078)" {
  printf '%s\n' '{"filesystem":"zfs","options":{"esp_size":"1G",
    "bootloader":"systemd-boot","kernel":["lts","default","hardened","zen"]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Kernels)"
  run guided_controller_list
  echo "$output" | grep -q "⚠ ESP too small"
}

@test "list(category Disks): esp_size auto never warns" {
  printf '%s\n' '{"filesystem":"zfs","options":{"esp_size":"auto",
    "kernel":["lts","default","hardened","zen"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  ! echo "$output" | grep -q "ESP too small"
}

@test "list(category Disks): the Disk layout row reflects the chosen preset" {
  printf '%s\n' "$(navigation_to_values Disks __layout__ "layout")" \
    > "$GUIDED_NAV_FILE"
  guided_controller_enter "os-mirror" >/dev/null    # apply the preset
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -q "Layout: OS: 2 disks (mirror)"
  echo "$output" | grep -q "●"               # overridden marker
}

@test "enter(category): an enum field opens the value picker" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_enter "Filesystem: ZFS"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "filesystem" ]
}

@test "enter(category): a text field opens the native query-line editor" {
  set_navigation "$(navigation_to_category System)"
  run guided_controller_enter "Hostname: "
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "system.hostname" ]
}

@test "enter(category): a toggle field opens the multi-select picker" {
  set_navigation "$(navigation_to_category Kernels)"
  run guided_controller_enter "Kernel: LTS"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.kernel" ]
}


# ── Cycle Fields: bare bools flip in place, no submenu (ADR 0075) ────────────

@test "is_cycle_field: bare bools yes; enums and editor-backed bools no" {
  for field in options.ssh.enabled options.pacman.color \
           post_install.security.antivirus post_install.backup.borg \
           options.printing.enabled options.bluetooth.enabled \
           environment.stock; do
    _controller_is_cycle_field "$field" || { echo "expected cycle: $field"; false; }
  done
  # options.power.profile is a 3-value ENUM (none/ppd/tuned), not a bool — it
  # must NOT be a Cycle Field, else the operator could never pick tuned/none
  # (ADR 0080).
  for field in filesystem options.bootloader options.kernel \
           environment.display_manager options.encryption \
           options.impermanence.enabled system.hostname \
           options.power.profile; do
    ! _controller_is_cycle_field "$field" || { echo "unexpected cycle: $field"; false; }
  done
}

# The Power enum's value picker must offer the three backends (regression: the
# render seam was wired but _controller_enum_options was not, so it fell through to
# true/false and the field was misclassified as a bool — ADR 0080).
@test "enum_options: power profile offers none / ppd / tuned, not true/false" {
  run _controller_enum_options options.power.profile
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx power-profiles-daemon
  echo "$output" | grep -qx tuned
  echo "$output" | grep -qx none
  ! echo "$output" | grep -qx true
}

# menu_owned_programs is the union every control owns (ADR 0086): the service
# programs (ADR 0079/0080), grub (Bootloader), the Security/Backup sets, sops.
@test "menu_owned_programs unions every control-owned program" {
  run menu_owned_programs
  [ "$status" -eq 0 ]
  for program in cups bluetooth power-profiles-daemon tuned grub firewalld ufw \
           clamav rkhunter apparmor borg zfs-auto-snapshot sops reflector; do
    grep -qx "$program" <<<"$output" || { echo "missing owned: $program"; false; }
  done
}

# Every Menu-Owned Program is filtered from the host picker (ADR 0086,
# generalising ADR 0079/0080). All six kind:host programs are owned, so the host
# picker keeps only a genuinely free-standing host program.
@test "host-programs picker omits every Menu-Owned program, keeps free ones" {
  mkdir -p "$INSTALLER_DIR/programs/printing/cups" \
           "$INSTALLER_DIR/programs/system/bluetooth" \
           "$INSTALLER_DIR/programs/power/power-profiles-daemon" \
           "$INSTALLER_DIR/programs/power/tuned" \
           "$INSTALLER_DIR/programs/bootloader/grub" \
           "$INSTALLER_DIR/programs/security/sops" \
           "$INSTALLER_DIR/programs/system/myhostprog"
  printf '{"name":"cups","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/printing/cups/config.jsonc"
  printf '{"name":"bluetooth","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/system/bluetooth/config.jsonc"
  printf '{"name":"power-profiles-daemon","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/power/power-profiles-daemon/config.jsonc"
  printf '{"name":"tuned","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/power/tuned/config.jsonc"
  printf '{"name":"grub","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/bootloader/grub/config.jsonc"
  printf '{"name":"sops","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/security/sops/config.jsonc"
  printf '{"name":"myhostprog","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/system/myhostprog/config.jsonc"
  program_registry_build

  run _controller_host_program_names
  [ "$status" -eq 0 ]
  for program in cups bluetooth power-profiles-daemon tuned grub sops; do
    ! grep -qx "$program" <<<"$output"      # Menu-Owned, filtered out
  done
  grep -qx myhostprog <<<"$output"    # free-standing host program stays
}

# The User Editor's programs picker drops Menu-Owned user programs (clamav,
# firewalld, borg, …) and keeps only free-standing ones (ADR 0086).
@test "user-programs picker omits Menu-Owned user programs, keeps free ones" {
  mkdir -p "$INSTALLER_DIR/programs/security/clamav" \
           "$INSTALLER_DIR/programs/security/firewalld" \
           "$INSTALLER_DIR/programs/backup/borg" \
           "$INSTALLER_DIR/programs/virtualization/docker" \
           "$INSTALLER_DIR/programs/communication/teamspeak3"
  printf '{"name":"clamav","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/security/clamav/config.jsonc"
  printf '{"name":"firewalld","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/security/firewalld/config.jsonc"
  printf '{"name":"borg","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/backup/borg/config.jsonc"
  printf '{"name":"docker","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/virtualization/docker/config.jsonc"
  printf '{"name":"teamspeak3","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/communication/teamspeak3/config.jsonc"
  program_registry_build

  run _controller_user_program_names
  [ "$status" -eq 0 ]
  ! grep -qx clamav <<<"$output"      # Security-owned
  ! grep -qx firewalld <<<"$output"   # Security-owned
  ! grep -qx borg <<<"$output"        # Backup-owned
  grep -qx docker <<<"$output"        # free-standing user program stays
  grep -qx teamspeak3 <<<"$output"
}

# Empty host picker (all host programs owned) is a clean success, not grep rc 1.
@test "host-programs picker is empty and rc 0 when all host progs are owned" {
  mkdir -p "$INSTALLER_DIR/programs/bootloader/grub"
  printf '{"name":"grub","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/bootloader/grub/config.jsonc"
  program_registry_build

  run _controller_host_program_names
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "enter(category): a bare bool flips in place (refresh, no drill)" {
  set_navigation "$(navigation_to_category Expert)"
  run guided_controller_enter "SSH: false"
  [ "$output" = "refresh" ]                                   # stays on category
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]   # no values submenu
  [ "$(jq -c '.options.ssh.enabled' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(category): flipping a default-true bool reads it true and turns it off" {
  _seed_baseline
  set_navigation "$(navigation_to_category Pacman)"
  run guided_controller_enter "Color: true"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.options.pacman.color' "$GUIDED_STATE_FILE")" = "false" ]
  config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" options.pacman.color
}

@test "enter(category): flipping a bool back to its default clears the override" {
  _seed_baseline
  set_navigation "$(navigation_to_category Expert)"
  guided_controller_enter "SSH: false" >/dev/null   # default false → true, override kept
  config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" options.ssh.enabled
  set_navigation "$(navigation_to_category Expert)"
  guided_controller_enter "SSH: true"  >/dev/null   # true → back to default false, drop
  ! config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" options.ssh.enabled
}

# environment.stock (ADR 0112): the Environment stock Cycle Field flips in place,
# stores the override, and normalises out when flipped back to its default off.
@test "enter(category): environment.stock flips on, stores, then clears on flip-back" {
  _seed_baseline
  set_navigation "$(navigation_to_category Environment)"
  run guided_controller_enter "Stock: true"         # default true → false, override kept
  [ "$output" = "refresh" ]
  [ "$(jq -c '.environment.stock' "$GUIDED_STATE_FILE")" = "false" ]
  config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" environment.stock
  set_navigation "$(navigation_to_category Environment)"
  guided_controller_enter "Stock: false" >/dev/null # false → back to default true, drop
  ! config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" environment.stock
}

@test "header(category): the hint advertises cycle" {
  run _controller_navigation_header "$(navigation_to_category Expert)"
  echo "$output" | grep -q "Enter edit / cycle"
}

@test "list(category Packages): drills repo/aur/derived, no field rows" {
  set_navigation "$(navigation_to_category Packages)"
  run guided_controller_list
  echo "$output" | grep -qE '^repo ▸'
  echo "$output" | grep -qE '^aur ▸'
  echo "$output" | grep -qE '^derived ▸'
  # Both former field rows are gone (ADR 0086): Packages is a pure drill now.
  ! echo "$output" | grep -qi "Extra packages:"
  ! echo "$output" | grep -qi "Host programs:"
}

@test "list(category): an empty VALUE keeps its column (no dot-shift)" {
  # regression: a tab-IFS read collapses an empty value field and shifts the
  # overridden flag into it — an empty hostname must render "Hostname: " not
  # "Hostname: false"/"…True".
  set_navigation "$(navigation_to_category System)"
  run guided_controller_list
  echo "$output" | grep -qE '^Hostname: *$'
  ! echo "$output" | grep -qiE '^Hostname: (true|false)'
}

@test "list(text esp size): current shows the default auto, not (unset)" {
  set_navigation "$(navigation_to_text Disks options.esp_size "esp size")"
  run guided_controller_list
  echo "$output" | grep -q "current: auto"
}


# ── multi-select toggle screens (native — never leaves fzf) ──────────────────

@test "list(values toggle): options are marked [x]/[ ] by selection" {
  printf '%s\n' '{"options":{"kernel":["lts"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Kernels options.kernel kernel)"
  run guided_controller_list
  echo "$output" | grep -q "\[x\] LTS"
  echo "$output" | grep -q "\[ \] Zen"
}

@test "enter(values toggle): toggling on adds the option and STAYS on the screen" {
  set_navigation "$(navigation_to_values Kernels options.kernel kernel)"
  run guided_controller_enter "[ ] lts"
  [ "$output" = "refresh" ]   # reload-sync in place (no flicker, query kept)
  [ "$(jq -c '.options.kernel' "$GUIDED_STATE_FILE")" = '["lts"]' ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
}

@test "directive→action: refresh re-lists in place via reload-sync" {
  run _controller_directive_to_action refresh /x/entry.sh
  [ "$output" = "reload-sync(bash /x/entry.sh list)+refresh-preview" ]
}

@test "enter(values toggle): toggling an already-selected option removes it" {
  printf '%s\n' '{"options":{"kernel":["lts","zen"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Kernels options.kernel kernel)"
  run guided_controller_enter "[x] zen"
  [ "$(jq -c '.options.kernel' "$GUIDED_STATE_FILE")" = '["lts"]' ]
}

@test "enter(values toggle): the last option toggled off unsets the override" {
  printf '%s\n' '{"options":{"kernel":["lts"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Kernels options.kernel kernel)"
  run guided_controller_enter "[x] lts"
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(values toggle gpu): auto is mutually exclusive → scalar auto" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Environment environment.gpu gpu)"
  run guided_controller_enter "[ ] auto"
  [ "$(jq -r '.environment.gpu' "$GUIDED_STATE_FILE")" = "auto" ]
}

@test "enter(values toggle gpu): picking a vendor clears auto" {
  printf '%s\n' '{"environment":{"gpu":"auto"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Environment environment.gpu gpu)"
  run guided_controller_enter "[ ] nvidia"
  [ "$(jq -c '.environment.gpu' "$GUIDED_STATE_FILE")" = '["nvidia"]' ]
}

@test "enter(values toggle gpu): AMD + NVIDIA select together (hybrid Legion)" {
  # the Legion 5 hybrid case, driven through the DISPLAYED labels (AMD/NVIDIA),
  # so it also exercises the Display Label reverse lookup for gpu.
  printf '%s\n' '{"environment":{"gpu":"auto"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Environment environment.gpu gpu)"
  guided_controller_enter "[ ] AMD" >/dev/null       # clears auto, adds amd
  [ "$(jq -c '.environment.gpu' "$GUIDED_STATE_FILE")" = '["amd"]' ]
  guided_controller_enter "[ ] NVIDIA" >/dev/null    # adds the second vendor
  [ "$(jq -c '.environment.gpu' "$GUIDED_STATE_FILE")" = '["amd","nvidia"]' ]
}
