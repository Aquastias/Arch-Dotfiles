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
source "${BASH_SOURCE[0]%/*}/../jsonc.sh"

# config_apply_plan <programs-json> <ships-home-json> <exclude-json>
#   programs-json:    array of program names selected for a user.
#   ships-home-json:  array of program names that ship a `home/` tree.
#   exclude-json:     array of the user's `config_exclude` names.
#   → JSON array of program names whose config applies, in selection order,
#     deduped. Pure: no filesystem, no globals.
config_apply_plan() {
  jq -n \
    --argjson progs "$1" \
    --argjson ships "$2" \
    --argjson excl  "$3" '
      [ $progs[]
        | . as $p
        | select($ships | index($p))
        | select(($excl | index($p)) | not)
        | $p ]
      | reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)
    '
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
  jq -n \
    --argjson ships "$1" \
    --argjson excl  "$2" \
    --argjson only  "$3" \
    --argjson optin "${4:-[]}" '
      if ($only | length) > 0
      then [ $only[]  | . as $p | select($ships | index($p)) | $p ]
      else [ $ships[] | . as $p
             | select(($excl | index($p)) | not)
             | select(($optin | index($p)) | not) | $p ]
      end
    '
}

# config_apply_stow_opted_in_programs <programs-root> — JSON array of every
# program whose config.jsonc sets `"stow_opt_in": true`.
config_apply_stow_opted_in_programs() {
  local root="$1" config_file program_directory
  [[ -d "$root" ]] || { printf '[]\n'; return 0; }
  {
    for config_file in "$root"/*/*/config.jsonc; do
      [[ -f "$config_file" ]] || continue
      [[ "$(jsonc_read_optional "$config_file" .stow_opt_in)" == true ]] \
        || continue
      program_directory="${config_file%/*}"
      printf '%s\n' "${program_directory##*/}"
    done
  } | jq -R . | jq -s -c 'unique'
}

# config_apply_ships_home_list <programs-root> — JSON array of every program
# name (the leaf basename) with a `home/` dir under
# <programs-root>/<cat>/<name>/home.
config_apply_ships_home_list() {
  local root="$1"
  [[ -d "$root" ]] || { printf '[]\n'; return 0; }
  local home_directory name
  {
    for home_directory in "$root"/*/*/home; do
      [[ -d "$home_directory" ]] || continue
      name="${home_directory%/*}"
      name="${name##*/}"
      printf '%s\n' "$name"
    done
  } | jq -R . | jq -s -c 'unique'
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
