#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/binds.sh — keybind parsers + expectations (ADR 0152)
# =============================================================================
# Every shipped keybind is parsed from the real config (never a hand list)
# into `source<TAB>chord<TAB>action` rows. An `audit-binds.jsonc` beside the
# owning config declares the observable effect per bind; `check` fails on a
# parsed bind with no expectation, the live keybind phase sends each one as
# real input and asserts its effect.
#
# audit-binds.jsonc:
#   { "expect": [
#       { "chord": "Mod+Shift+E" | "action": "<glob>",
#         "effect": "<effect>", "arg": "<text|{arg}>",
#         "session_ending": bool, "recovery": "session|unlock",
#         "reason": "<why>"  // effect "unverifiable" only
#       } ] }
# A chord match wins over an action glob; `{arg}` is the action's argument.
#
# Public API:
#   fa_binds_sources                 → registered source ids
#   fa_binds_parse <src> <file…>     → rows from the given config files
#   fa_binds_rows <src>              → rows from the shipped config
#   fa_binds_expect_file <src>       → the source's audit-binds.jsonc path
#   fa_binds_plan <src> [files… binds-file]  → one JSON object per row
#   fa_binds_untested <src> [files… binds-file] → rows lacking an expectation
# =============================================================================

FA_REPO_ROOT="${FA_REPO_ROOT:-$(cd "$INSTALLER_DIR/.." && pwd)}"

# Registry: source → "session|config-glob|expectations" (repo-relative).
declare -gA FA_BIND_SOURCES=(
  [niri]="niri|.config/niri/conf.d/*.kdl|.installer/extras/desktop/niri/audit-binds.jsonc"
)

fa_binds_sources() { printf '%s\n' "${!FA_BIND_SOURCES[@]}" | sort; }

_fa_binds_field() {
  local spec="${FA_BIND_SOURCES[$1]:-}"
  [[ -n "$spec" ]] || return 1
  cut -d'|' -f"$2" <<<"$spec"
}

fa_binds_session() { _fa_binds_field "$1" 1; }

fa_binds_expect_file() {
  printf '%s/%s\n' "$FA_REPO_ROOT" "$(_fa_binds_field "$1" 3)"
}

# _fa_binds_files <src> — the shipped config files for a source.
_fa_binds_files() {
  local g; g="$(_fa_binds_field "$1" 2)" || return 1
  # shellcheck disable=SC2086 # intentional glob expansion
  ls -1 "$FA_REPO_ROOT"/$g 2>/dev/null
}

# _fa_parse_niri <file…> — KDL `binds { Chord [props] { action; } }` blocks.
_fa_parse_niri() {
  awk '
    function flush() {
      gsub(/[;[:space:]]+$/, "", act); gsub(/^[[:space:]]+/, "", act)
      gsub(/;[[:space:]]*/, "; ", act); sub(/; $/, "", act)
      if (chord != "") printf "niri\t%s\t%s\n", chord, act
      chord = ""; act = ""
    }
    { sub(/^[[:space:]]*\/\/.*$/, "") }
    /^[[:space:]]*binds[[:space:]]*\{/ { inb = 1; depth = 1; next }
    !inb { next }
    {
      line = $0
      if (depth == 1) {
        if (line ~ /^[[:space:]]*\}/) { inb = 0; next }
        if (line !~ /\{/) next
        split(line, f, " "); chord = f[1]; sub(/^[[:space:]]+/, "", chord)
        body = line; sub(/^[^{]*\{/, "", body)
        depth = 2
      } else body = line
      if (body ~ /\}[[:space:]]*$/) {
        sub(/\}[[:space:]]*$/, "", body); act = act " " body; flush()
        depth = 1
      } else act = act " " body
    }
  ' "$@"
}

# fa_binds_parse <src> <file…>
fa_binds_parse() {
  local src="$1"; shift
  case "$src" in
    niri) _fa_parse_niri "$@" ;;
    *) echo "feature-audit: no bind parser for '$src'" >&2; return 1 ;;
  esac
}

fa_binds_rows() {
  local -a files; mapfile -t files < <(_fa_binds_files "$1")
  ((${#files[@]})) || { echo "feature-audit: no config for '$1'" >&2; return 1; }
  fa_binds_parse "$1" "${files[@]}"
}

# fa_binds_plan <src> [config-file… expectations-file] — the matched plan.
fa_binds_plan() {
  local src="$1"; shift
  local rows exp
  if (($#)); then
    exp="${*: -1}"
    rows="$(fa_binds_parse "$src" "${@:1:$#-1}")" || return 1
  else
    exp="$(fa_binds_expect_file "$src")"
    rows="$(fa_binds_rows "$src")" || return 1
  fi
  local ej='{"expect":[]}'
  [[ -f "$exp" ]] && ej="$(jsonc_strip "$exp" | jq -c .)"
  jq -R -c --argjson e "$ej" '
    def glob2re: gsub("(?<c>[.+?^$()\\[\\]{}|\\\\])"; "\\\(.c)")
                 | gsub("\\*"; ".*") | "^" + . + "$";
    split("\t") as [$s, $chord, $act]
    | ($act | capture("^[^ ]+ +(?<a>.*)$").a // "" | gsub("^\"|\"$"; ""))
        as $arg
    | ([$e.expect[] | select(.chord == $chord)]
       + [$e.expect[] | select(.action and (.chord | not))
          | select(. as $x | $act | test($x.action | glob2re))])[0] as $m
    | { source: $s, chord: $chord, action: $act }
      + (if $m then ($m | del(.chord, .action))
           + { arg: (($m.arg // "") | gsub("\\{arg\\}"; $arg)) }
         else { effect: null } end)
  ' <<<"$rows"
}

fa_binds_untested() {
  fa_binds_plan "$@" | jq -r 'select(.effect == null)
    | "\(.source)\t\(.chord)\t\(.action)"'
}
