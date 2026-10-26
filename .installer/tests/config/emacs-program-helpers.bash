# emacs-program-helpers.bash — shared setup for the dev/emacs program tests
# (ADR 0160): emacs-program.bats (program, pin, hook, look, toolchain) and
# emacs-program-parity.bats (keys, theme, org, REST, debugging). Static seam:
# the COMMITTED files, read with grep/awk — no install run, no Emacs runtime.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."   # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/emacs"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOOK="$PROG/post-config.sh"
  PIN="$PROG/doom-ref"
  DOOMDIR="$PROG/home/.config/doom"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  OPERATOR="$REPO/.installer/users/aquastias/profile.jsonc"
  # shellcheck source=../../lib/jsonc.sh
  source "$REPO/.installer/lib/jsonc.sh"
}

COVERAGE_REL=.installer/programs/dev/emacs/coverage.txt
LANGS_REL=.installer/programs/dev/nvim/home/.config/nvim/lua/config
LANGS_REL=$LANGS_REL/languages.lua   # the Language Registry
FLEET_REL=.installer/hosts/fleet/profile.jsonc

# data_rows FILE → the file's lines, `#` comments and blanks dropped.
data_rows() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# elisp FILE → the file with `;` comments stripped (no string has a `;`).
elisp() { awk '{ sub(/;.*/, ""); if ($0 ~ /[^[:space:]]/) print }' "$1"; }

# module_enabled <module-form> → status 0 when init.el's doom! block enables it
# (e.g. `(evil +everywhere)` or `vertico`) on an uncommented line.
module_enabled() {
  elisp "$DOOMDIR/init.el" | grep -qF -- "$1"
}

# registry_keys → the Language Registry's language keys (ADR 0141), read from
# nvim's languages.lua with awk — no Lua runtime.
registry_keys() {
  awk '/^local registry = \{/ { on = 1; next }
       on && /^}/ { exit }
       on && match($0, /^  [a-z_]+ = /) {
         k = substr($0, 3); sub(/ = .*/, "", k); print k }' \
    "$REPO/$LANGS_REL"
}

# bound <key> <command> → status 0 when config.el binds the key (a map! key
# string; leader keys space-separated) straight to the named command.
bound() {
  elisp "$DOOMDIR/config.el" | grep -qF "\"$1\" #'$2" \
    || { echo "unbound: $1 → $2"; return 1; }
}

