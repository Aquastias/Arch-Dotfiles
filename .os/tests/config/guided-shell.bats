#!/usr/bin/env bats
# Tests for .os/lib/guided.sh — the Guided Installer's fzf shell (ADR 0039).
# The shell is impure glue, but its selection seam (guided_select /
# guided_prompt) is replayable: under a GUIDED_REPLAY answers file the menu
# is driven headlessly, no fzf, no tty. So guided_build — the assembly path —
# is exercised deterministically here; the fzf rendering stays smoke-only.
#
# Behaviour under test (external only — the Effective Config a replayed
# session assembles, and the INSTALL consent gate), never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  # Mirror common.sh faithfully: info/warn/section echo to STDOUT, error to
  # stderr. guided_build's only stdout MUST be the Effective Config — any human
  # output (the review screen) has to be redirected, so these stdout stubs are
  # the guard that catches stdout pollution.
  info()    { echo "[info] $*"; }
  warn()    { echo "[warn] $*"; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { echo "== $* =="; }
  export -f info warn error section

  mkdir -p "$OS_DIR/hosts/core"
  printf '%s\n' \
    '{"system_programs":["cups"],"sysctl":{"vm.swappiness":10}}' \
    > "$OS_DIR/hosts/core/profile.jsonc"

  # Real pure cores (emit pulls in the real picker_assign_disks + layers).
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"

  # Stub only the live-disk enumeration (no lsblk in tests); picker_assign_disks
  # stays real so the assembled config is the genuine artifact.
  live_medium_disks() { :; }
  picker_enum_disks() { printf '%s\n' "/dev/disk/by-id/wwn-0xDEAD"; }
  export -f live_medium_disks picker_enum_disks

  # shellcheck source=../../lib/guided.sh
  source "$BATS_TEST_DIRNAME/../../lib/guided.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_answers() {
  local f="$TEST_DIR/answers"
  printf '%s\n' "$@" > "$f"
  printf '%s' "$f"
}

# queue <choice...> — script a sequence of fzf selections in a file, popped one
# per call by the fzf stub below. File-backed so it advances across the `… |
# fzf` subshell (a counter in the stub would only mutate the subshell). An
# empty queue returns non-zero, the same as an Esc, so a loop can never hang.
queue() { printf '%s\n' "$@" > "$TEST_DIR/queue"; }
fzf_queue() {
  fzf() {
    cat >/dev/null
    local q="$TEST_DIR/queue" line
    [ -s "$q" ] || return 1
    line="$(head -n1 "$q")"
    sed -i '1d' "$q"
    printf '%s\n' "$line"
  }
  export -f fzf
}

# ── tracer: a replayed session assembles the single-disk Effective Config ───

@test "guided_build: a replayed session assembles the Effective Config" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  # stdout is the Effective Config; the review screen goes to stderr.
  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.hostname == "eterniox"'
  echo "$effective" | jq -e '.mode == "single"'
  echo "$effective" | jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"'
  echo "$effective" | jq -e '.system_programs == ["cups"]'
}

# ── a replayed session carries the Disks choices into the Effective Config ──

@test "guided_build: a replayed session emits filesystem/encryption/impermanence/persist" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'filesystem=zfs' \
    'encryption=true' \
    'impermanence=true' \
    'persist_dir=/etc/wireguard' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.filesystem == "zfs"'
  echo "$effective" | jq -e '.options.encryption == true'
  echo "$effective" | jq -e '.options.impermanence.enabled == true'
  echo "$effective" | jq -e '.persist.directories == ["/etc/wireguard"]'
}

# ── a replayed session carries the Options + Environment choices (issue 05) ─

@test "guided_build: a replayed session emits Options + Environment fields" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'kernel=zen lts' \
    'bootloader=grub' \
    'swap=false' \
    'swap_size=8G' \
    'esp_size=4G' \
    'ssh=true' \
    'age_key_url=https://example.test/key.age' \
    'desktop=kde hyprland' \
    'gpu=amd nvidia' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.options.kernel == ["zen","lts"]'
  echo "$effective" | jq -e '.options.bootloader == "grub"'
  echo "$effective" | jq -e '.options.swap == false'
  echo "$effective" | jq -e '.options.swap_size == "8G"'
  echo "$effective" | jq -e '.options.esp_size == "4G"'
  echo "$effective" | jq -e '.options.ssh.enabled == true'
  echo "$effective" | jq -e '.options.age_key_url == "https://example.test/key.age"'
  echo "$effective" | jq -e '.environment.desktop == ["kde","hyprland"]'
  echo "$effective" | jq -e '.environment.gpu == ["amd","nvidia"]'
}

# ── a replayed session carries Pacman + Packages + Advanced (issue 06 Pass B)

@test "guided_build: a replayed session emits Pacman/Packages/Advanced fields" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'mirror_countries=Japan Australia' \
    'multilib=false' \
    'package=htop tmux' \
    'sysctl=vm.swappiness=20' \
    'dotfiles_repo=https://github.com/me/dots' \
    'backup=true' \
    'security=true' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.options.mirror_countries == ["Japan","Australia"]'
  echo "$effective" | jq -e '.options.multilib == false'
  echo "$effective" | jq -e '.packages.extra == ["htop","tmux"]'
  echo "$effective" | jq -e '.sysctl["vm.swappiness"] == 20'
  echo "$effective" | jq -e '.dotfiles_repo == "https://github.com/me/dots"'
  echo "$effective" | jq -e '.post_install.backup == true'
  echo "$effective" | jq -e '.post_install.security == true'
}

# ── Advanced freeform authoring: build an arbitrary skeleton group by group ─

@test "_guided_author_skeleton: replay authors the OS pool + a storage group" {
  guided_load_replay "$(write_answers \
    'adv_os_topology=mirror' 'adv_os_disk_count=2' \
    'adv_storage_count=1' 'adv_storage_0_name=data' \
    'adv_storage_0_topology=raidz1' 'adv_storage_0_disk_count=3' \
    'adv_data_count=0')"
  _GUIDED_STATE="$(cfgstate_new)"

  _guided_author_skeleton
  echo "$_GUIDED_STATE" | jq -e '.mode == "multi"'
  echo "$_GUIDED_STATE" | jq -e '.os_pool.topology == "mirror"'
  echo "$_GUIDED_STATE" | jq -e '.storage_groups[0].name == "data"'
  echo "$_GUIDED_STATE" | jq -e '.storage_groups[0].disk_count == 3'
}

@test "guided_build: a replayed Advanced session bakes the authored skeleton" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=advanced' \
    'adv_os_topology=mirror' 'adv_os_disk_count=2' \
    'adv_storage_count=1' 'adv_storage_0_name=data' \
    'adv_storage_0_topology=raidz1' 'adv_storage_0_disk_count=3' \
    'adv_data_count=0' \
    'disks=/dev/disk/by-id/A /dev/disk/by-id/B /dev/disk/by-id/C /dev/disk/by-id/D /dev/disk/by-id/E' \
    'accept_layout=ACCEPT' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.os_pool.topology == "mirror"'
  echo "$effective" | jq -e '(.os_pool.disks | length) == 2'
  echo "$effective" | jq -e '.storage_groups[0].topology == "raidz1"'
  echo "$effective" | jq -e '(.storage_groups[0].disks | length) == 3'
}

# ── a replayed MULTI-disk session bakes the preset skeleton's disks (issue 04)

@test "guided_build: a replayed os-mirror session bakes the 2-disk OS mirror" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=os-mirror' \
    'disks=/dev/disk/by-id/wwn-A /dev/disk/by-id/wwn-B' \
    'accept_layout=ACCEPT' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.mode == "multi"'
  echo "$effective" | jq -e '.os_pool.topology == "mirror"'
  echo "$effective" | jq -e \
    '.os_pool.disks == ["/dev/disk/by-id/wwn-A","/dev/disk/by-id/wwn-B"]'
}

@test "guided_build: a multi session with the wrong disk count aborts" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=os-mirror' \
    'disks=/dev/disk/by-id/wwn-A' \
    'accept_layout=ACCEPT' \
    'confirm=INSTALL')"

  run guided_build
  [ "$status" -ne 0 ]
}

# ── the config must carry the back-end's required identity fields ───────────
# (validation.sh requires system.locale + system.timezone; the tracer defaults
#  them — issue 05 turns these into live-system-picked menu rows.)

@test "guided_build: the config carries the required identity defaults" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  echo "$effective" | jq -e '.system.locale and .system.timezone'
  echo "$effective" | jq -e '.system.keymap'
}

# ── the interactive menu renders the Host/Users split with values + ● ───────
# _guided_menu_lines is the pure core the fzf loop displays; the fzf navigation
# itself is smoke-only.

@test "_guided_menu_lines: renders the Host/Users split, values, override flag" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run _guided_menu_lines "$state"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hostname: eterniox"   # edited value shown
  echo "$output" | grep -q "●"                     # overridden row flagged
  echo "$output" | grep -q "filesystem: zfs"       # Disks-first, zfs default
  echo "$output" | grep -q "Users"                 # the Host/Users split
}

# ── the re-entrant loop: select a field, edit it, return, Proceed ───────────
# fzf is stubbed (its selection driven by current state) so the loop's dispatch
# — render → select → edit → re-enter → Proceed — is exercised deterministically.

@test "_guided_menu_loop: edits hostname then Proceeds (fzf stubbed)" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"   # disk already picked

  # First pass (no hostname yet) → pick the hostname row; next pass → Proceed.
  fzf() {
    cat >/dev/null
    if [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]; then
      echo "Host · hostname: (none)"
    else
      echo "Proceed ▸ review & install"
    fi
  }
  guided_prompt() { printf '%s' "newhost"; }
  export -f fzf guided_prompt

  _guided_menu_loop
  local rc=$?
  [ "$rc" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" = "newhost" ]
}

# ── Undo in the loop reverts an edit without losing the rest (non-destructive)
# fzf is stubbed to replay a scripted sequence of menu choices; the loop drives
# its dispatch deterministically (render → select → edit/undo → Proceed).

@test "_guided_menu_loop: editing then Undo reverts the edit, then Proceeds" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  # Pick the hostname row, then Undo, then Proceed.
  fzf_queue
  queue "Host · hostname: (none)" "Undo ◂ last change" \
        "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "newhost"; }
  export -f guided_prompt

  _guided_menu_loop      # direct (not `run`) so state mutates in the test shell
  [ "$?" -eq 0 ]
  # the hostname edit was committed, then undone → back to unset
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]
}

# ── Reset-all confirms first, then discards every override ──────────────────

@test "_guided_menu_loop: Reset-all (confirmed) discards the overrides" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset all ▸ discard every change" "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "RESET"; }   # confirm the wipe
  export -f guided_prompt

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]   # override gone
}

@test "_guided_menu_loop: Reset-all (declined) keeps the overrides" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset all ▸ discard every change" "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "no"; }      # decline the wipe
  export -f guided_prompt

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" = "eterniox" ]  # kept
}

# ── the footer surfaces undo/redo only when available, Reset-all always ─────
# _guided_footer_lines is the pure core the loop appends below the rows; the
# fzf draw is smoke-only.

@test "_guided_footer_lines: a fresh history offers only Reset-all" {
  h="$(hist_new "$(cfgstate_new)")"

  run _guided_footer_lines "$h"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Reset all"
  ! echo "$output" | grep -q "Undo"
  ! echo "$output" | grep -q "Redo"
}

@test "_guided_footer_lines: a committed change offers Undo (not Redo)" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(cfgstate_set "$(cfgstate_new)" mode '"single"')")"

  run _guided_footer_lines "$h"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Undo"
  echo "$output" | grep -q "Reset all"
  ! echo "$output" | grep -q "Redo"
}

@test "_guided_footer_lines: after an undo, Redo is offered" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(cfgstate_set "$(cfgstate_new)" mode '"single"')")"
  h="$(hist_undo "$h")"

  run _guided_footer_lines "$h"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Redo"
}

# ── Reset field in the loop: pick one overridden field and clear it (undoable)

@test "_guided_menu_loop: Reset field clears the picked override" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset field ▸ clear one field" "Proceed ▸ review & install"
  guided_select() { printf '%s' "system.hostname"; }   # pick the field to clear
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" ]
}

# ── Reset section in the loop: clear every override in the picked section ────

@test "_guided_menu_loop: Reset section clears the picked section's overrides" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" filesystem '"zfs"')"  # Disks
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Reset section ▸ clear one section" "Proceed ▸ review & install"
  guided_select() { printf '%s' "Disks"; }             # pick the Disks section
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" filesystem)" ]                # Disks cleared
  [ "$(cfgstate_get "$_GUIDED_STATE" system.hostname)" = "eterniox" ] # Host kept
}

# ── granular reset: a menu section's overrides clear, the rest survives ─────
# _guided_reset_section is pure (menu_rows + cfgstate_unset); it clears only the
# section's *menu* fields, so the seeded identity (not a row) is preserved.

@test "_guided_reset_section: clears a section's overrides, keeps the rest" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" filesystem '"zfs"')"
  state="$(cfgstate_set "$state" system.locale '"de_DE.UTF-8"')"  # seeded, no row

  run _guided_reset_section "$state" Host
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system | has("hostname") | not'   # Host row cleared
  echo "$output" | jq -e '.filesystem == "zfs"'              # Disks row preserved
  echo "$output" | jq -e '.system.locale == "de_DE.UTF-8"'   # non-row preserved
}

# ── the granular reset actions appear only when there is something to clear ──

@test "_guided_reset_lines: offered only when the state carries overrides" {
  run _guided_reset_lines "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  run _guided_reset_lines "$state"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Reset field"
  echo "$output" | grep -q "Reset section"
}

# ── filesystem-first Disks: zfs is active, btrfs/ext4/xfs reserved (ADR 0040)

@test "_guided_filesystem_options: zfs is active, the others are reserved" {
  run _guided_filesystem_options
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "zfs"
  echo "$output" | grep -q "btrfs (reserved)"
  echo "$output" | grep -q "ext4 (reserved)"
  echo "$output" | grep -q "xfs (reserved)"
}

@test "_guided_edit_filesystem: picking zfs commits the filesystem" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "zfs"; }
  export -f guided_select

  _guided_edit_filesystem
  [ "$(cfgstate_get "$_GUIDED_STATE" filesystem)" = "zfs" ]
}

@test "_guided_edit_filesystem: a reserved filesystem is refused, no commit" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "btrfs (reserved)"; }
  export -f guided_select

  run _guided_edit_filesystem
  [ "$status" -ne 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" filesystem)" ]
}

# ── a multi-disk layout lets Proceed succeed without a single install disk ──

@test "_guided_menu_loop: choosing a multi layout enables Proceed (no single disk)" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _guided_set_identity          # mode starts single
  _GUIDED_DISK=""               # and no single install disk picked

  fzf_queue
  queue "Disk layout ▸ choose preset" "Proceed ▸ review & install"
  guided_select() { printf '%s' "os-mirror"; }
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" mode)" = "multi" ]
  [ "$(cfgstate_get "$_GUIDED_STATE" os_pool.topology)" = "mirror" ]
}

# ── the loop dispatches the Disks rows to their edits (label-keyed) ─────────

@test "_guided_menu_loop: editing the encryption row enables it" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Disks · encryption: false" "Proceed ▸ review & install"
  guided_select() { printf '%s' "true"; }   # the bool pick
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" options.encryption)" = "true" ]
}

@test "_guided_menu_loop: editing the bootloader row commits the pick" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Options · bootloader: systemd-boot" "Proceed ▸ review & install"
  guided_select() { printf '%s' "grub"; }
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" options.bootloader)" = "grub" ]
}

@test "_guided_menu_loop: editing the gpu row commits vendors (Environment)" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Environment · gpu: auto" "Proceed ▸ review & install"
  guided_multi() { printf '%s\n' "amd"; }
  export -f guided_multi

  _guided_menu_loop
  [ "$?" -eq 0 ]
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == ["amd"]'
}

@test "_guided_menu_loop: editing the multilib row commits the toggle" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Pacman · multilib: true" "Proceed ▸ review & install"
  guided_select() { printf '%s' "false"; }
  export -f guided_select

  _guided_menu_loop
  [ "$?" -eq 0 ]
  [ "$(cfgstate_get "$_GUIDED_STATE" options.multilib)" = "false" ]
}

@test "_guided_menu_loop: the Add-sysctl action commits a literal sysctl key" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Add sysctl ▸ key=value" "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "kernel.sysrq=1"; }
  export -f guided_prompt

  _guided_menu_loop
  [ "$?" -eq 0 ]
  echo "$_GUIDED_STATE" | jq -e '.sysctl["kernel.sysrq"] == 1'
}

@test "_guided_menu_loop: with impermanence on, Add persist appends a dir" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" \
    options.impermanence.enabled 'true')"
  _GUIDED_DISK="/dev/disk/by-id/wwn-0xDEAD"

  fzf_queue
  queue "Add persist directory ▸ extend the curated defaults" \
        "Proceed ▸ review & install"
  guided_prompt() { printf '%s' "/etc/wireguard"; }
  export -f guided_prompt

  _guided_menu_loop
  [ "$?" -eq 0 ]
  echo "$_GUIDED_STATE" | jq -e '.persist.directories == ["/etc/wireguard"]'
}

# ── encryption / impermanence are bool toggles through the seam ─────────────

@test "_guided_edit_encryption: selecting true enables encryption" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_encryption
  echo "$_GUIDED_STATE" | jq -e '.options.encryption == true'
}

@test "_guided_edit_impermanence: selecting true enables impermanence" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_impermanence
  echo "$_GUIDED_STATE" | jq -e '.options.impermanence.enabled == true'
}

# ── persist extensions: free-text directories appended for impermanence ─────

@test "_guided_add_persist: appends a directory to persist.directories" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "/etc/wireguard"; }
  export -f guided_prompt

  _guided_add_persist
  echo "$_GUIDED_STATE" | jq -e '.persist.directories == ["/etc/wireguard"]'
}

@test "_guided_add_persist: empty input adds nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_add_persist
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.persist == null'
}

# ── the persist-extension action surfaces only when impermanence is enabled ─

@test "_guided_persist_lines: offered only when impermanence is enabled" {
  run _guided_persist_lines "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  state="$(cfgstate_set "$(cfgstate_new)" options.impermanence.enabled 'true')"
  run _guided_persist_lines "$state"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "persist"
}

# ── Pacman + Advanced edits (issue 06 Pass B): reuse the issue-05 helpers ───

@test "_guided_edit_mirror_countries: multi-select stores the country array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "Japan" "Australia"; }
  export -f guided_multi

  _guided_edit_mirror_countries
  echo "$_GUIDED_STATE" | jq -e '.options.mirror_countries == ["Japan","Australia"]'
}

@test "_guided_edit_multilib: selecting false disables multilib" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "false"; }
  export -f guided_select

  _guided_edit_multilib
  echo "$_GUIDED_STATE" | jq -e '.options.multilib == false'
}

@test "_guided_edit_dotfiles_repo: a typed URL commits dotfiles_repo" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "https://github.com/me/dots"; }
  export -f guided_prompt

  _guided_edit_dotfiles_repo
  echo "$_GUIDED_STATE" | jq -e '.dotfiles_repo == "https://github.com/me/dots"'
}

@test "_guided_edit_backup: selecting true enables the backup extra" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_backup
  echo "$_GUIDED_STATE" | jq -e '.post_install.backup == true'
}

# ── list builders: packages.extra / system_programs / sysctl ────────────────

@test "_guided_add_package: typed names (whitespace-split) append to extra" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "htop tmux"; }
  export -f guided_prompt

  _guided_add_package
  echo "$_GUIDED_STATE" | jq -e '.packages.extra == ["htop","tmux"]'
}

@test "_guided_add_package: empty input adds nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_add_package
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.packages == null'
}

@test "_guided_add_system_program: picked names append, deduped" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system_programs '["cups"]')"
  guided_multi() { printf '%s\n' "docker" "cups"; }   # cups already present
  export -f guided_multi

  _guided_add_system_program
  echo "$_GUIDED_STATE" | jq -e '.system_programs | index("docker")'
  echo "$_GUIDED_STATE" \
    | jq -e '([.system_programs[] | select(. == "cups")] | length) == 1'
}

@test "_guided_add_sysctl: a key=value sets a literal (dotted) sysctl key" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "vm.swappiness=10"; }
  export -f guided_prompt

  _guided_add_sysctl
  # the dotted key is a literal object key, value stored as a number
  echo "$_GUIDED_STATE" | jq -e '.sysctl["vm.swappiness"] == 10'
}

@test "_guided_add_sysctl: a malformed entry (no =) commits nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "not-a-pair"; }
  export -f guided_prompt

  run _guided_add_sysctl
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.sysctl == null'
}

# ── the multi-select seam: a replayed answer is the whitespace-separated list

@test "guided_multi: a replayed answer yields one option per line, in order" {
  guided_load_replay "$(write_answers 'kernel=zen lts')"
  run guided_multi kernel "Kernels" lts default hardened zen
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | sed -n 1p)" = "zen" ]
  [ "$(echo "$output" | sed -n 2p)" = "lts" ]
}

# ── Options edits: kernel is a token list, primary (first picked) first ─────

@test "_guided_edit_kernel: multi-select stores the token array, primary first" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "zen" "lts"; }
  export -f guided_multi

  _guided_edit_kernel
  echo "$_GUIDED_STATE" | jq -e '.options.kernel == ["zen","lts"]'
}

@test "_guided_edit_kernel: no pick leaves the kernel untouched" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { :; }
  export -f guided_multi

  run _guided_edit_kernel
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.options.kernel == null'
}

# ── bootloader / swap-size / ssh: simple scalar + bool edits ───────────────

@test "_guided_edit_bootloader: picking grub commits the bootloader" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "grub"; }
  export -f guided_select

  _guided_edit_bootloader
  echo "$_GUIDED_STATE" | jq -e '.options.bootloader == "grub"'
}

@test "_guided_edit_swap_size: a typed size commits options.swap_size" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "8G"; }
  export -f guided_prompt

  _guided_edit_swap_size
  echo "$_GUIDED_STATE" | jq -e '.options.swap_size == "8G"'
}

@test "_guided_edit_swap_size: empty input commits nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_edit_swap_size
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.options.swap_size == null'
}

@test "_guided_edit_ssh: selecting true enables ssh" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_ssh
  echo "$_GUIDED_STATE" | jq -e '.options.ssh.enabled == true'
}

# ── Environment: desktop is a multi, gpu auto clears vendors ────────────────

@test "_guided_edit_desktop: multi-select stores the desktop array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "kde" "hyprland"; }
  export -f guided_multi

  _guided_edit_desktop
  echo "$_GUIDED_STATE" | jq -e '.environment.desktop == ["kde","hyprland"]'
}

@test "_guided_edit_gpu: vendors store an array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "amd" "nvidia"; }
  export -f guided_multi

  _guided_edit_gpu
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == ["amd","nvidia"]'
}

@test "_guided_edit_gpu: auto stores the scalar and clears any vendors" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "auto" "amd"; }   # auto wins, vendors dropped
  export -f guided_multi

  _guided_edit_gpu
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == "auto"'
}

# ── the typed INSTALL is the sole consent gate ─────────────────────────────

@test "guided_build: aborts with no config when INSTALL is not typed" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=nope')"

  run guided_build
  [ "$status" -ne 0 ]
  # nothing installable leaks to stdout
  refute_json() { ! echo "$1" | jq -e 'has("mode")' 2>/dev/null; }
  refute_json "$(guided_build 2>/dev/null)"
}
