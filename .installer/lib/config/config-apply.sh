#!/usr/bin/env bash
# =============================================================================
# lib/config/config-apply.sh — Config Apply Planner (ADR 0134)
# =============================================================================
# Decides which selected Programs' `home/` config to apply for a user. Config
# is decoupled from package install: `install.sh` installs the package, this
# module (via the Runner pass and `./stow-configs.sh`) applies the config.
#
# `config_apply_plan` is pure (JSON in, JSON out).
# `config_apply_ships_home_list`, `config_apply_home_directory` and
# `config_apply_stow_opted_in_programs` walk the programs tree — a Program ships
# config iff it has a `home/` dir (discovery by convention, no registry).
#
# Apply rule (from the design prototype):
#   apply(program) = selected && ships_home(program) && !config_exclude(program)
#
# Public API:
#   config_apply_plan <programs-json> <ships-home-json> <exclude-json>
#       → plan (array)
#   config_apply_ships_home_list <programs-root> → names (array)
#   config_apply_home_directory <programs-root> <name> → absolute home/ path
#   config_apply_stow_selection <ships> <except> <only> [<opt-in>]
#       → names (array)
#   config_apply_stow_opted_in_programs <programs-root> → names (array)
#
# Used by: lib/profiles/runner.sh (and the staged chroot runtime).
# =============================================================================

# shellcheck source=../jsonc.sh
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

source "${BASH_SOURCE[0]%/*}/../jsonc.sh"

# config_apply_plan <programs-json> <ships-home-json> <exclude-json>
#   programs-json:    array of program names selected for a user.
#   ships-home-json:  array of program names that ship a `home/` tree.
#   exclude-json:     array of the user's `config_exclude` names.
#   → JSON array of program names whose config applies, in selection order,
#     deduped. Pure: no filesystem, no globals.
config_apply_plan() {
  local plan='[$progs[] | . as $p | select(($ships | index($p))'
  plan+=' and (($excl | index($p)) | not))]'
  # Each name kept once, at its first place.
  plan+=' | . as $a | [range(length) as $i | $a[$i]'
  plan+=' | . as $x | select(($a | index($x)) == $i)]'
  # The selected programs that ship a home/ and are not excluded.
  jq -n \
    --argjson progs "$1" \
    --argjson ships "$2" \
    --argjson excl  "$3" "$plan"
}

# config_apply_stow_selection <ships-json> <except-json> <only-json>
#   The `./stow-configs.sh` wrapper's pure selection logic.
#   ships-json:  every program that ships a `home/`
#                (config_apply_ships_home_list order).
#   except-json:  names to skip (the `--except` flag); ignored when a name
#                 ships no home.
#   only-json:    an explicit positional subset; when non-empty it wins over
#                 `except`, keeps its own order, and drops any name that ships
#                 no home.
#   opt-in-json:  `stow_opt_in` programs (optional, default []): dropped from
#                 the no-arg sweep, kept when named (ADR 0148).
#   → ordered JSON array of program names to stow. Pure.
config_apply_stow_selection() {
  local selection='if ($only | length) > 0'
  selection+=' then [$only[] | . as $p | select($ships | index($p))]'
  selection+=' else [$ships[] | . as $p | select(($excl | index($p)) | not)'
  selection+=' | select(($optin | index($p)) | not)] end'
  # The programs to stow.
  jq -n \
    --argjson ships "$1" \
    --argjson excl  "$2" \
    --argjson only  "$3" \
    --argjson optin "${4:-[]}" "$selection"
}

# _config_apply_name_list — stdin's names (one per line) as a sorted JSON
# array, each once.
_config_apply_name_list() {
  local names unique='$names | split("\n") | map(select(length > 0)) | unique'
  names="$(cat)"
  # The names as a sorted JSON array, each once.
  jq -cn --arg names "$names" "$unique"
}

# config_apply_stow_opted_in_programs <programs-root> — JSON array of every
# program whose config.jsonc sets `"stow_opt_in": true`.
config_apply_stow_opted_in_programs() {
  local root="$1" config_file
  [[ -d "$root" ]] || { printf '[]\n'; return 0; }
  for config_file in "$root"/*/*/config.jsonc; do
    [[ -f "$config_file" ]] || continue
    [[ "$(jsonc_read_optional "$config_file" .stow_opt_in)" == true ]] \
      || continue
    # The program: the directory the config.jsonc is in.
    basename "$(dirname "$config_file")"
  done | _config_apply_name_list
}

# config_apply_ships_home_list <programs-root> — JSON array of every program
# name (the leaf basename) with a `home/` dir under
# <programs-root>/<cat>/<name>/home.
config_apply_ships_home_list() {
  local root="$1"
  [[ -d "$root" ]] || { printf '[]\n'; return 0; }
  local homes names
  # Each <cat>/<name>/home under the root.
  homes="$(find "$root" -mindepth 3 -maxdepth 3 -type d -name home \
    -printf '%P\n' 2>/dev/null)"
  # Their <name>s, hidden directories left out (as a glob would).
  names="$(printf '%s\n' "$homes" | grep -v '^\.\|/\.' | cut -d/ -f2)"
  printf '%s\n' "$names" | _config_apply_name_list
}

# config_apply_home_directory <programs-root> <name> — echo the absolute `home/`
# path for a program name, or return 1 if the program has none. Matches
# <programs-root>/<cat>/<name>/home for any category.
config_apply_home_directory() {
  local root="$1" name="$2" home_directory
  for home_directory in "$root"/*/"$name"/home; do
    [[ -d "$home_directory" ]] || continue
    printf '%s\n' "$home_directory"
    return 0
  done
  return 1
}
