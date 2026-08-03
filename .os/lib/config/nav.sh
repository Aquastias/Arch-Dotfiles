#!/usr/bin/env bash
# =============================================================================
# lib/config/nav.sh — Guided Installer navigation state (ADR 0042)
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
# =============================================================================

# nav_new — the launch screen.
nav_new() { printf '%s\n' '{"screen":"top"}'; }

# nav_screen <nav> — the current screen token.
nav_screen() { jq -r '.screen' <<<"$1"; }

# nav_get <nav> <key> — category | field | label (empty when absent).
nav_get() { jq -r --arg k "$2" '.[$k] // empty' <<<"$1"; }

# nav_to_category <category> — drill into a category.
nav_to_category() { jq -nc --arg c "$1" '{screen:"category", category:$c}'; }

# nav_to_profiles — the Profiles picker screen (ADR 0055): a top-level drill
# that lists the installable Host Profiles; picking one seeds the menu.
nav_to_profiles() { printf '%s\n' '{"screen":"profiles"}'; }

# nav_to_newhost — the `+ New host` confirm screen (ADR 0063): a full session
# reset is destructive, so the picker drills here before resetting. Back returns
# to the profiles picker.
nav_to_newhost() { printf '%s\n' '{"screen":"newhost"}'; }

# nav_to_rooteditor <category> — the Root Editor (ADR 0063): root's password +
# shell behind one editor, symmetric with the per-user editor. Carries the
# category so nav_back returns to the flattened Users list.
nav_to_rooteditor() { jq -nc --arg c "$1" '{screen:"rooteditor",category:$c}'; }

# nav_to_values <category> <field> <label> — open a field's value picker.
nav_to_values() {
  jq -nc --arg c "$1" --arg f "$2" --arg l "$3" \
    '{screen:"values", category:$c, field:$f, label:$l}'
}

# nav_to_text <category> <field> <label> — open a field's free-text editor
# (slice 02; slice 01 free-text routes through the one-shot prompt instead).
nav_to_text() {
  jq -nc --arg c "$1" --arg f "$2" --arg l "$3" \
    '{screen:"text", category:$c, field:$f, label:$l}'
}

# nav_to_swapedit <category> — the swap sub-editor (enabled / size / zswap).
nav_to_swapedit() { jq -nc --arg c "$1" '{screen:"swapedit", category:$c}'; }

# nav_to_encryption <category> — the Encryption Editor (ADR 0059): the toggle +
# the disk passphrase, collapsed behind one Disks row. Modelled on the swap
# sub-editor.
nav_to_encryption() {
  jq -nc --arg c "$1" '{screen:"encryption", category:$c}'
}

# nav_to_impermanence <category> — the Impermanence Editor (ADR 0066): the
# enablement toggle + persist-directory management collapsed behind one Disks
# row, modelled on the swap / encryption sub-editors. nav_back → Disks category.
nav_to_impermanence() {
  jq -nc --arg c "$1" '{screen:"impermanence", category:$c}'
}

# nav_to_datapools <category> — the data-pools list editor.
nav_to_datapools() { jq -nc --arg c "$1" '{screen:"datapools", category:$c}'; }

# nav_to_pooledit <category> <index> [kind] — edit one pool group. <kind> is the
# group reference (os | storage | data), defaulting to data for back-compat; the
# controller resolves the group through (kind, index) — see _ctl_pool_get.
nav_to_pooledit() {
  jq -nc --arg c "$1" --argjson i "$2" --arg k "${3:-data}" \
    '{screen:"pooledit", category:$c, index:$i, kind:$k}'
}

# nav_to_pooldisks <category> <index> <kind> — the In-Menu Disk Binding
# sub-screen for one pool group: toggle its bound /dev/disk/by-id/* devices.
nav_to_pooldisks() {
  jq -nc --arg c "$1" --argjson i "$2" --arg k "${3:-data}" \
    '{screen:"pooldisks", category:$c, index:$i, kind:$k}'
}

# nav_to_rootdisk <category> — the single-disk-root picker (single-select one
# /dev/disk/by-id/* device for a single-disk install).
nav_to_rootdisk() { jq -nc --arg c "$1" '{screen:"rootdisk", category:$c}'; }

# nav_to_useredit <category> <name> — the per-user User Editor (ADR 0051): edit
# one user's profile fields (shell, …). Carries the user name so every edit is
# scoped back to that user; nav_back returns to the flattened Users list.
nav_to_useredit() {
  jq -nc --arg c "$1" --arg u "$2" \
    '{screen:"useredit", category:$c, user:$u}'
}

# nav_to_clone <category> <source> — the clone name-entry text screen (0064):
# a __cloneuser__ text field carrying the SOURCE user, so the commit copies that
# user's account-shape into the newly-named clone. Modelled on nav_to_text +
# __newuser__, plus the carried source; nav_back returns to the Users category.
nav_to_clone() {
  jq -nc --arg c "$1" --arg u "$2" \
    '{screen:"text", category:$c, field:"__cloneuser__",
      label:("clone of " + $u), user:$u}'
}

# nav_to_secret <category> <target> [user] [phase] [origin-json] — the inline
# masked password screen (ADR 0051). target is root | user | enc; user names the
# account for a user password; phase is entry | confirm (type-twice). Carries no
# secret — the typed value lives in the tmpfs buffer file, never the nav.
#
# origin-json (ADR 0059), when given, is the nav to return to on cancel or save.
# Declaring it once at open time replaces re-deriving the return screen from the
# target in two separate places (nav_back and the confirm path).
nav_to_secret() {
  local c="$1" t="$2" u="${3:-}" p="${4:-entry}" o="${5:-}"
  if [[ -n "$o" ]]; then
    jq -nc --arg c "$c" --arg t "$t" --arg u "$u" --arg p "$p" \
      --argjson o "$o" \
      '{screen:"secret", category:$c, target:$t, user:$u, phase:$p, origin:$o}'
  else
    jq -nc --arg c "$c" --arg t "$t" --arg u "$u" --arg p "$p" \
      '{screen:"secret", category:$c, target:$t, user:$u, phase:$p}'
  fi
}

# nav_secret_return <secret-nav> — the screen a masked capture returns to on
# cancel (Esc) or save (confirm); both land in the same place, so the return is
# read from one carried `origin` field. Absent it (older hand-built navs), fall
# back to the pre-0059 target+category derivation: the disk passphrase opened on
# Disks returns to that category, every other secret to the Users list.
nav_secret_return() {
  jq -c '
    if .origin then .origin
    elif .target == "enc" and .category == "Disks"
      then {screen:"category", category:.category}
    else {screen:"values", category:.category, field:"users", label:"users"}
    end' <<<"$1"
}

# nav_to_userfield <category> <user> <field> <label> — a user-scoped sub-editor
# (ADR 0051): the multi (groups/programs), text (git.name/git.email) or list
# (ssh) field of one user. Carries the user so the commit writes that user's
# install-scoped delta; nav_back returns to the user's editor.
nav_to_userfield() {
  jq -nc --arg c "$1" --arg u "$2" --arg f "$3" --arg l "$4" \
    '{screen:"userfield", category:$c, user:$u, field:$f, label:$l}'
}

# nav_to_poolmount <category> <index> — the free-text editor for data_pools[index]'s
# mount point (ADR 0047). A text screen that carries the pool index so the commit
# is scoped back to the right pool, then returns to that pool's editor.
nav_to_poolmount() {
  jq -nc --arg c "$1" --argjson i "$2" \
    '{screen:"text", category:$c, field:"__poolmount__", label:"mount", index:$i}'
}

# ── Packages screen (ADR 0058) ──────────────────────────────────────────────
# Two drill levels mirroring the Categorized List shape the JSONC uses:
#   pkgcat — the categories inside one slot (repo|aur), with counts
#   pkgs   — the package toggles inside one category
# plus the read-only derived pair (pkgderived → pkgderivedsrc).

# nav_to_pkgcat <category> <slot> — the category list inside repo/aur.
nav_to_pkgcat() {
  jq -nc --arg c "$1" --arg s "$2" \
    '{screen:"pkgcat", category:$c, slot:$s}'
}

# nav_to_pkgs <category> <slot> <pkgcat> — the package toggles in one category.
nav_to_pkgs() {
  jq -nc --arg c "$1" --arg s "$2" --arg k "$3" \
    '{screen:"pkgs", category:$c, slot:$s, pkgcat:$k}'
}

# nav_to_pkgderived <category> — the read-only derived source list.
nav_to_pkgderived() {
  jq -nc --arg c "$1" '{screen:"pkgderived", category:$c}'
}

# nav_to_pkgderivedsrc <category> <source> — one derived source's package list.
nav_to_pkgderivedsrc() {
  jq -nc --arg c "$1" --arg s "$2" \
    '{screen:"pkgderivedsrc", category:$c, source:$s}'
}

# nav_back <nav> — values/text → their category; category → top; top stays top.
# The secret screen routes through nav_secret_return so its cancel path reads
# the same carried origin the save path does (ADR 0059).
nav_back() {
  if [[ "$(jq -r '.screen' <<<"$1")" == "secret" ]]; then
    nav_secret_return "$1"; return
  fi
  jq -c '
    if   .screen == "profiles"
         then {screen:"top"}
    elif .screen == "newhost"
         then {screen:"profiles"}
    elif .screen == "rooteditor"
         then {screen:"values",category:.category,field:"users",label:"users"}
    elif .screen == "values" and .field == "users"
         then {screen:"top"}
    elif .screen == "values" or .screen == "text"
         then {screen:"category", category:.category}
    elif .screen == "swapedit"  then {screen:"category", category:.category}
    elif .screen == "encryption" then {screen:"category", category:.category}
    elif .screen == "impermanence" then {screen:"category", category:.category}
    elif .screen == "datapools" then {screen:"category", category:.category}
    elif .screen == "pooledit"  then {screen:"datapools", category:.category}
    elif .screen == "pooldisks"
         then {screen:"pooledit", category:.category,
               index:.index, kind:.kind}
    elif .screen == "rootdisk" then {screen:"category", category:.category}
    elif .screen == "useredit"
         then {screen:"values", category:.category, field:"users", label:"users"}
    elif .screen == "userfield"
         then {screen:"useredit", category:.category, user:.user}
    elif .screen == "pkgcat" then {screen:"category", category:.category}
    elif .screen == "pkgs"
         then {screen:"pkgcat", category:.category, slot:.slot}
    elif .screen == "pkgderived"
         then {screen:"category", category:.category}
    elif .screen == "pkgderivedsrc"
         then {screen:"pkgderived", category:.category}
    elif .screen == "category" then {screen:"top"}
    else {screen:"top"} end' <<<"$1"
}
