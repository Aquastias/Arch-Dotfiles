#!/usr/bin/env bash
# =============================================================================
# lib/config/seed.sh — Guided Installer default seeder (ADR 0039)
# =============================================================================
# A pure helper over Config State: it fills a launch state with this operator's
# computed defaults so an untouched guided run is ready to install. Independent
# of menu rendering — it writes only Config State, so it survives the menu
# rewrite. Pure: a Config State in, the seeded Config State out, no TTY.
#
# Public API:
#   cfgstate_seed_defaults <state>  → <state> with the launch defaults set
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_set)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# cfgstate_seed_defaults <state> — overlay the launch defaults onto <state>.
cfgstate_seed_defaults() {
  local state="$1"
  state="$(cfgstate_set "$state" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" users '["aquastias"]')"
  state="$(cfgstate_set "$state" mode '"single"')"
  state="$(cfgstate_set "$state" system.locale '"en_US.UTF-8"')"
  state="$(cfgstate_set "$state" system.timezone '"Europe/Bucharest"')"
  state="$(cfgstate_set "$state" system.keymap '"us"')"
  printf '%s\n' "$state"
}
