#!/usr/bin/env bash
# =============================================================================
# lib/config/navigation.sh — Guided Installer navigation state (ADR 0042)
# =============================================================================
# The persistent-fzf controller is invoked by fzf binds as SUBPROCESSES, so the
# "which screen am I on" state can't live in a shell variable — it lives in a
# tmpfs file the controller reads and transitions through these pure verbs.
#
# Screens:
#   top      — the Configuration Categories + the terminal-action rows
#   category — one category's field rows + its category-local actions
#   values   — picking an enumerable value for a field
#   text     — typing a free-text value for a field (slice 02)
#
# Pure: JSON in/out, no TTY.
#
# Used by: lib/guided/controller.sh.
# =============================================================================

# navigation_new — the launch screen.
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

navigation_new() { printf '%s\n' '{"screen":"top"}'; }

# navigation_screen <nav> — the current screen token.
navigation_screen() { printf '%s\n' "$1" | jq -r '.screen'; }

# navigation_get <nav> <key> — category | field | label (empty when absent).
navigation_get() { printf '%s\n' "$1" | jq -r --arg k "$2" '.[$k] // empty'; }

# navigation_to_category <category> — drill into a category.
navigation_to_category() {
  # The category screen.
  jq -nc --arg c "$1" '{screen:"category", category:$c}'
}

# navigation_to_profiles — the Profiles picker screen (ADR 0055): a top-level
# drill that lists the installable Host Profiles; picking one seeds the menu.
navigation_to_profiles() { printf '%s\n' '{"screen":"profiles"}'; }

# navigation_to_new_host — the `+ New host` confirm screen (ADR 0063): a full
# session reset is destructive, so the picker drills here before resetting. Back
# returns to the profiles picker.
navigation_to_new_host() { printf '%s\n' '{"screen":"newhost"}'; }

# _navigation_to <screen> <category> — a screen that carries only its
# category (the sub-editors and pickers below).
_navigation_to() {
  # The screen, with its category.
  jq -nc --arg s "$1" --arg c "$2" '{screen:$s, category:$c}'
}

# navigation_to_root_editor <category> — the Root Editor (ADR 0063): root's
# password + shell behind one editor, symmetric with the per-user editor.
# Carries the category so navigation_back returns to the flattened Users list.
navigation_to_root_editor() { _navigation_to rooteditor "$1"; }

# _navigation_to_field <screen> <category> <field> <label> — a screen editing
# one field.
_navigation_to_field() {
  local template='{screen:$s, category:$c, field:$f, label:$l}'
  # The field's screen.
  jq -nc --arg s "$1" --arg c "$2" --arg f "$3" --arg l "$4" "$template"
}

# navigation_to_values <category> <field> <label> — open a field's value picker.
navigation_to_values() { _navigation_to_field values "$@"; }

# navigation_to_text <category> <field> <label> — open a field's free-text
# editor (slice 02; slice 01 free-text routes through the one-shot prompt
# instead).
navigation_to_text() { _navigation_to_field text "$@"; }

# navigation_to_swap_edit <category> — the swap sub-editor (enabled / size /
# zswap).
navigation_to_swap_edit() { _navigation_to swapedit "$1"; }

# navigation_to_manual_partitions <category> — the Manual Partitioning
# assignment table (ADR 0073): the cfdisk hand-off action + one row per
# partition. navigation_to_partition_edit <category> <device> — the
# per-partition editor (mountpoint / filesystem / format) opened from a
# partition row.
navigation_to_manual_partitions() { _navigation_to manualparts "$1"; }
navigation_to_partition_edit() {
  local template='{screen:"partedit", category:$c, device:$d}'
  # The partition editor, with its device.
  jq -nc --arg c "$1" --arg d "$2" "$template"
}

# navigation_to_encryption <category> — the Encryption Editor (ADR 0059): the
# toggle + the disk passphrase, collapsed behind one Disks row. Modelled on the
# swap sub-editor.
navigation_to_encryption() { _navigation_to encryption "$1"; }

# navigation_to_impermanence <category> — the Impermanence Editor (ADR 0066):
# the enablement toggle + persist-directory management collapsed behind one
# Disks row, modelled on the swap / encryption sub-editors. navigation_back →
# Disks category.
navigation_to_impermanence() { _navigation_to impermanence "$1"; }

# navigation_to_data_pools <category> — the data-pools list editor.
navigation_to_data_pools() { _navigation_to datapools "$1"; }

# _navigation_to_pool <screen> <category> <index> [kind] — a screen editing
# one pool group (kind defaults to data).
_navigation_to_pool() {
  local template='{screen:$s, category:$c, index:$i, kind:$k}'
  # The pool's screen.
  jq -nc --arg s "$1" --arg c "$2" --argjson i "$3" --arg k "${4:-data}" \
    "$template"
}

# navigation_to_pool_edit <category> <index> [kind] — edit one pool group.
# <kind> is the group reference (os | storage | data), defaulting to data for
# back-compat; the controller resolves the group through (kind, index) — see
# _controller_pool_get.
navigation_to_pool_edit() { _navigation_to_pool pooledit "$@"; }

# navigation_to_pool_disks <category> <index> <kind> — the In-Menu Disk Binding
# sub-screen for one pool group: toggle its bound /dev/disk/by-id/* devices.
navigation_to_pool_disks() { _navigation_to_pool pooldisks "$@"; }

# navigation_to_root_disk <category> — the single-disk-root picker
# (single-select one /dev/disk/by-id/* device for a single-disk install).
navigation_to_root_disk() { _navigation_to rootdisk "$1"; }

# navigation_to_user_edit <category> <name> — the per-user User Editor (ADR
# 0051): edit one user's profile fields (shell, …). Carries the user name so
# every edit is scoped back to that user; navigation_back returns to the
# flattened Users list.
navigation_to_user_edit() {
  local template='{screen:"useredit", category:$c, user:$u}'
  # The user's editor.
  jq -nc --arg c "$1" --arg u "$2" "$template"
}

# navigation_to_clone <category> <source> — the clone name-entry text screen
# (0064): a __cloneuser__ text field carrying the SOURCE user, so the commit
# copies that user's account-shape into the newly-named clone. Modelled on
# navigation_to_text + __newuser__, plus the carried source; navigation_back
# returns to the Users category.
navigation_to_clone() {
  local template='{screen:"text", category:$c, field:"__cloneuser__",'
  template+=' label:("clone of " + $u), user:$u}'
  # The clone's name-entry screen.
  jq -nc --arg c "$1" --arg u "$2" "$template"
}

# navigation_to_secret <category> <target> [user] [phase] [origin-json] — the
# inline masked password screen (ADR 0051). target is root | user | enc; user
# names the account for a user password; phase is entry | confirm (type-twice).
# Carries no secret — the typed value lives in the tmpfs buffer file, never the
# nav.
#
# origin-json (ADR 0059), when given, is the nav to return to on cancel or save.
# Declaring it once at open time replaces re-deriving the return screen from the
# target in two separate places (navigation_back and the confirm path).
navigation_to_secret() {
  local category="$1" target="$2" user="${3:-}" phase="${4:-entry}"
  local origin="${5:-null}"
  local template='{screen:"secret", category:$c, target:$t, user:$u, phase:$p}'
  template+=' + (if $o == null then {} else {origin:$o} end)'
  # The secret screen (with its origin, when given).
  jq -nc --arg c "$category" --arg t "$target" --arg u "$user" \
    --arg p "$phase" --argjson o "$origin" "$template"
}

# navigation_secret_return <secret-nav> — the screen a masked capture returns to
# on cancel (Esc) or save (confirm); both land in the same place, so the return
# is read from one carried `origin` field. Absent it (older hand-built navs),
# fall back to the pre-0059 target+category derivation: the disk passphrase
# opened on Disks returns to that category, every other secret to the Users
# list.
navigation_secret_return() {
  local back='if .origin then .origin'
  back+=' elif .target == "enc" and .category == "Disks"'
  back+=' then {screen:"category", category:.category}'
  back+=' else {screen:"values", category:.category, field:"users",'
  back+=' label:"users"} end'
  # The screen to return to.
  printf '%s\n' "$1" | jq -c "$back"
}

# navigation_to_user_field <category> <user> <field> <label> — a user-scoped
# sub-editor (ADR 0051): the multi (groups/programs), text (git.name/git.email)
# or list (ssh) field of one user. Carries the user so the commit writes that
# user's install-scoped delta; navigation_back returns to the user's editor.
navigation_to_user_field() {
  local template='{screen:"userfield", category:$c, user:$u,'
  template+=' field:$f, label:$l}'
  # The user's field screen.
  jq -nc --arg c "$1" --arg u "$2" --arg f "$3" --arg l "$4" "$template"
}

# navigation_to_pool_mount <category> <index> — the free-text editor for
# data_pools[index]'s mount point (ADR 0047). A text screen that carries the
# pool index so the commit is scoped back to the right pool, then returns to
# that pool's editor.
navigation_to_pool_mount() {
  local template='{screen:"text", category:$c, field:"__poolmount__",'
  template+=' label:"mount", index:$i}'
  # The pool's mount-point editor.
  jq -nc --arg c "$1" --argjson i "$2" "$template"
}

# ── Packages screen (ADR 0058) ──────────────────────────────────────────────
# Two drill levels mirroring the Categorized List shape the JSONC uses:
#   pkgcat — the categories inside one slot (repo|aur), with counts
#   pkgs   — the package toggles inside one category
# plus the read-only derived pair (pkgderived → pkgderivedsrc).

# _navigation_to_slot <screen> <category> <slot> — a screen inside one
# package slot (repo | aur).
_navigation_to_slot() {
  local template='{screen:$s, category:$c, slot:$l}'
  # The slot's screen.
  jq -nc --arg s "$1" --arg c "$2" --arg l "$3" "$template"
}

# navigation_to_package_category <category> <slot> — the category list inside
# repo/aur.
navigation_to_package_category() { _navigation_to_slot pkgcat "$@"; }

# navigation_to_packages <category> <slot> <pkgcat> — the package toggles in one
# category.
navigation_to_packages() {
  local template='{screen:"pkgs", category:$c, slot:$s, pkgcat:$k}'
  # The package toggles of one category.
  jq -nc --arg c "$1" --arg s "$2" --arg k "$3" "$template"
}

# navigation_to_package_browse <category> <slot> — the full repo package browser
# (ADR 0086): every pacman -Slq package as toggle rows IN the persistent fzf, so
# ＋Add needs no execute() hand-off (which flashed the bare tty). Back returns to
# the slot's category list.
navigation_to_package_browse() { _navigation_to_slot pkgbrowse "$@"; }

# navigation_to_package_derived <category> — the read-only derived source list.
navigation_to_package_derived() { _navigation_to pkgderived "$1"; }

# navigation_to_package_derived_source <category> <source> — one derived
# source's package list.
navigation_to_package_derived_source() {
  local template='{screen:"pkgderivedsrc", category:$c, source:$s}'
  # The derived source's package list.
  jq -nc --arg c "$1" --arg s "$2" "$template"
}

# navigation_back <nav> — values/text → their category; category → top; top
# stays top (navigation-back.jq). The secret screen routes through
# navigation_secret_return so its cancel path reads the same carried origin the
# save path does (ADR 0059).
#
# A back transition carries a `focus` hint naming the row it is returning ONTO —
# the category name for category→top, the field label for a field→category — so
# render restores the cursor there instead of leaving it on the reload's stale
# line index (a spacer/header). The hint is best-effort: render no-ops it when
# it matches no row, so only reliably-labelled screens set it.
navigation_back() {
  if [[ "$(navigation_screen "$1")" == "secret" ]]; then
    navigation_secret_return "$1"
    return
  fi
  # The screen Back returns to.
  printf '%s\n' "$1" | jq -c -f "${BASH_SOURCE[0]%/*}/navigation-back.jq"
}
