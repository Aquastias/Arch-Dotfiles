#!/usr/bin/env bash
# =============================================================================
# lib/config/config-apply.sh — Config Apply Planner (ADR 0134)
# =============================================================================
# Decides which selected Programs' `home/` config to apply for a user. Config
# is decoupled from package install: `install.sh` installs the package, this
# module (via the Runner pass and `./stow-configs`) applies the config.
#
# `ca_plan` is pure (JSON in, JSON out). `ca_ships_home_list` / `ca_home_dir`
# walk the programs tree — a Program ships config iff it has a `home/` dir
# (discovery by convention, no registry).
#
# Apply rule (from the design prototype):
#   apply(program) = selected && ships_home(program) && !config_exclude(program)
#
# Public API:
#   ca_plan <programs-json> <ships-home-json> <exclude-json>  → plan (array)
#   ca_ships_home_list <programs-root>                        → names (array)
#   ca_home_dir <programs-root> <name>                        → abs home/ path
# =============================================================================

# ca_plan <programs-json> <ships-home-json> <exclude-json>
#   programs-json:    array of program names selected for a user.
#   ships-home-json:  array of program names that ship a `home/` tree.
#   exclude-json:     array of the user's `config_exclude` names.
#   → JSON array of program names whose config applies, in selection order,
#     deduped. Pure: no filesystem, no globals.
ca_plan() {
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

# ca_stow_selection <ships-json> <except-json> <only-json>
#   The `./stow-configs` wrapper's pure selection logic.
#   ships-json:  every program that ships a `home/` (ca_ships_home_list order).
#   except-json:  names to skip (the `--except` flag); ignored when a name
#                 ships no home.
#   only-json:    an explicit positional subset; when non-empty it wins over
#                 `except`, keeps its own order, and drops any name that ships
#                 no home.
#   → ordered JSON array of program names to stow. Pure.
ca_stow_selection() {
  jq -n \
    --argjson ships "$1" \
    --argjson excl  "$2" \
    --argjson only  "$3" '
      if ($only | length) > 0
      then [ $only[]  | . as $p | select($ships | index($p)) | $p ]
      else [ $ships[] | . as $p | select(($excl | index($p)) | not) | $p ]
      end
    '
}

# ca_ships_home_list <programs-root> — JSON array of every program name (the
# leaf basename) with a `home/` dir under <programs-root>/<cat>/<name>/home.
ca_ships_home_list() {
  local root="$1"
  [[ -d "$root" ]] || { printf '[]\n'; return 0; }
  local d name
  {
    for d in "$root"/*/*/home; do
      [[ -d "$d" ]] || continue
      name="$(basename "$(dirname "$d")")"
      printf '%s\n' "$name"
    done
  } | jq -R . | jq -s -c 'unique'
}

# ca_home_dir <programs-root> <name> — echo the absolute `home/` path for a
# program name, or return 1 if the program has none. Matches
# <programs-root>/<cat>/<name>/home for any category.
ca_home_dir() {
  local root="$1" name="$2" d
  for d in "$root"/*/"$name"/home; do
    [[ -d "$d" ]] || continue
    printf '%s\n' "$d"
    return 0
  done
  return 1
}
