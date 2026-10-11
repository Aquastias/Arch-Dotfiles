# guided-menu-helpers.bash — shared setup for the guided-menu-*.bats parts
# Tests for .installer/lib/config/menu.sh — the Guided Installer's Menu model
# (ADR
# 0039): Config State → menu rows (section / label / value / ● override flag).
# It drives both the fzf shell and these tests, so the rows ARE the contract.
# Pure: JSON-in/JSON-out, no TTY.
#
# Behaviour under test (external only — the rows the model emits), never
# internal structure.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/config-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  # shellcheck source=../../lib/config/menu.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
}

row() { jq -e ".[] | select(.field == \"$1\")"; }
# menu_categories is the top-level contract: the ordered categories the operator
# drills into, in install-flow order under six buckets. Each carries a summary,
# a bucket, and an aggregated ● (any descendant field overridden). The list is
# the same fourteen regardless of state.

cat_at() { jq -e ".[$1]"; }

