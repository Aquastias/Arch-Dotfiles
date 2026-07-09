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

# nav_back <nav> — values/text → their category; category → top; top stays top.
nav_back() {
  jq -c '
    if   .screen == "values" or .screen == "text"
         then {screen:"category", category:.category}
    elif .screen == "swapedit"  then {screen:"category", category:.category}
    elif .screen == "datapools" then {screen:"category", category:.category}
    elif .screen == "pooledit"  then {screen:"datapools", category:.category}
    elif .screen == "pooldisks"
         then {screen:"pooledit", category:.category,
               index:.index, kind:.kind}
    elif .screen == "rootdisk" then {screen:"category", category:.category}
    elif .screen == "category" then {screen:"top"}
    else {screen:"top"} end' <<<"$1"
}
