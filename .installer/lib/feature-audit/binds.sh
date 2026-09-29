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
# A chord match wins over an action glob; `{arg}` is the action's argument,
# `{num}` its first number.
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

# Registry: source → "session|config|owner" (repo-relative). The owner dir
# holds the source's audit-binds.jsonc. A compositor source (session set)
# runs in the keybinds phase; a program source (session `-`) is staged to
# that program's probe as `binds-plan.jsonl` and driven by it; session `*` is
# an app bind sent as real input in the first compositor session.
# `find:<dir>:<name>` walks a tree.
_X=.installer/extras/desktop _P=.installer/programs
declare -gA FA_BIND_SOURCES=(
  [niri]="niri|.config/niri/conf.d/*.kdl|$_X/niri"
  [hyprland]="hyprland|.config/hypr/conf.d/*.lua|$_X/hyprland"
  [kde]="kde|$_X/kde/skel/.config/kglobalshortcutsrc|$_X/kde"
  [nvim]="-|find:$_P/dev/nvim/home/.config/nvim:*.lua|$_P/dev/nvim"
  [kitty]="*|$_P/system/kitty/home/.config/kitty/conf/*.conf|$_P/system/kitty"
  [zsh]="-|find:$_P/system/zsh/home:.z*|$_P/system/zsh"
)
unset _X _P

fa_binds_sources() { printf '%s\n' "${!FA_BIND_SOURCES[@]}" | sort; }

_fa_binds_field() {
  local spec="${FA_BIND_SOURCES[$1]:-}"
  [[ -n "$spec" ]] || return 1
  cut -d'|' -f"$2" <<<"$spec"
}

fa_binds_session() { _fa_binds_field "$1" 1; }

fa_binds_expect_file() {
  printf '%s/%s/audit-binds.jsonc\n' "$FA_REPO_ROOT" \
    "$(_fa_binds_field "$1" 3)"
}

# _fa_binds_files <src> — the shipped config files for a source.
_fa_binds_files() {
  local g; g="$(_fa_binds_field "$1" 2)" || return 1
  if [[ "$g" == find:* ]]; then
    g="${g#find:}"
    find "$FA_REPO_ROOT/${g%%:*}" -name "${g#*:}" -type f | sort
    return
  fi
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


# _fa_parse_hyprland <file…> — Lua `hl.bind(<key expr>, hl.dsp.<disp>(…))`:
# string locals, `..` concatenation and `for i = a, b do … end` are evaluated
# (a static read of what the compositor would register).
_fa_parse_hyprland() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function ev(e,   n, p, i, t, o) {
      n = split(e, p, /[ \t]*\.\.[ \t]*/); o = ""
      for (i = 1; i <= n; i++) {
        t = trim(p[i])
        if (t ~ /^".*"$/) o = o substr(t, 2, length(t) - 2)
        else if (t in loc) o = o loc[t]
        else o = o t
      }
      return o
    }
    function chord(k,   n, p, i, t, u, o) {
      n = split(k, p, /[ \t]*\+[ \t]*/); o = ""
      for (i = 1; i <= n; i++) {
        t = trim(p[i]); u = toupper(t)
        if (u == "SUPER" || u == "MOD4" || u == "WIN") t = "Super"
        else if (u == "CTRL" || u == "CONTROL") t = "Ctrl"
        else if (u == "SHIFT") t = "Shift"
        else if (u == "ALT") t = "Alt"
        o = o (o == "" ? "" : "+") t
      }
      return o
    }
    function bind(s,   i, c, q, key, rest, d, disp, n) {
      sub(/^.*hl\.bind\(/, "", s)
      q = 0; key = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\"") q = !q
        if (c == "," && !q) {
          key = substr(s, 1, i - 1); rest = substr(s, i + 1); break
        }
      }
      rest = trim(rest); sub(/^hl\.dsp\./, "", rest)
      q = 0; d = 0; disp = rest
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "\"") q = !q
        if (q) continue
        if (c == "(") d++
        if (c == ")" && --d == 0) { disp = substr(rest, 1, i); break }
      }
      for (n in loc)
        disp = gensub("\\(" n "\\)", "(\"" loc[n] "\")", "g", disp)
      printf "hyprland\t%s\t%s\n", chord(ev(key)), disp
    }
    /^[ \t]*--/ { next }
    { sub(/[ \t]+--[ \t].*$/, "") }
    /^[ \t]*local [A-Za-z_]+[ \t]*=[ \t]*"/ {
      n = $0; sub(/^[ \t]*local[ \t]+/, "", n); v = n
      sub(/[ \t]*=.*$/, "", n); sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
      loc[n] = v; next
    }
    /^[ \t]*for [A-Za-z_]+[ \t]*=[ \t]*[0-9]+[ \t]*,[ \t]*[0-9]+[ \t]*do/ {
      lv = $2; a = $4; sub(/,/, "", a); b = $5
      if (b == "") { split($4, ab, ","); a = ab[1]; b = ab[2] }
      a = gensub(/[^0-9]/, "", "g", a); b = gensub(/[^0-9]/, "", "g", b)
      inl = 1; nb = 0; next
    }
    inl && /^[ \t]*end[ \t]*$/ {
      for (v = a + 0; v <= b + 0; v++)
        for (j = 1; j <= nb; j++)
          bind(gensub("([^A-Za-z_\"])" lv "([^A-Za-z_\"]|$)", "\\1" v "\\2",
                      "g", buf[j]))
      inl = 0; next
    }
    inl { if ($0 ~ /hl\.bind\(/) buf[++nb] = $0; next }
    /hl\.bind\(/ { bind($0) }
  ' "$@"
}

# _fa_parse_kde <kglobalshortcutsrc…> — `Action=Active\tAlt,Default,Label`
# per [component]; every active shortcut (not `none`) is a row.
_fa_parse_kde() {
  awk '
    /^\[/ { g = substr($0, 2, length($0) - 2); next }
    /^_k_friendly_name=/ { next }
    index($0, "=") {
      name = substr($0, 1, index($0, "=") - 1)
      a = substr($0, index($0, "=") + 1); sub(/,.*$/, "", a)
      if (a == "none" || a == "") next
      n = split(a, ks, /\\t/)
      for (i = 1; i <= n; i++) {
        k = ks[i]
        if (k ~ /\+\+$/) k = substr(k, 1, length(k) - 2) "+Plus"
        if (k != "" && k != "none") printf "kde\t%s\t%s/%s\n", k, g, name
      }
    }
  ' "$@"
}

# _fa_parse_nvim <lua…> — see binds-nvim.awk.
_fa_parse_nvim() {
  local f
  for f in "$@"; do
    awk -f "$INSTALLER_DIR/lib/feature-audit/binds-nvim.awk" "$f"
  done
}

# _fa_parse_kitty <conf…> — `map <keys> <action>`; kitty_mod is ctrl+shift
# (kitty's default; the curated config does not rebind it).
_fa_parse_kitty() {
  awk '
    /^[ \t]*map[ \t]/ {
      k = $2; sub(/^[ \t]*map[ \t]+[^ \t]+[ \t]+/, "")
      gsub(/kitty_mod/, "ctrl+shift", k)
      n = split(k, p, "+"); o = ""
      for (i = 1; i <= n; i++) {
        t = p[i]
        if (t == "ctrl") t = "Ctrl"; else if (t == "shift") t = "Shift"
        else if (t == "alt") t = "Alt"; else if (t == "super") t = "Super"
        o = o (o == "" ? "" : "+") t
      }
      printf "kitty\t%s\t%s\n", o, $0
    }' "$@"
}

# _fa_parse_zsh <rc…> — explicit `bindkey [-M map] <seq> <widget>` lines
# (a bare `bindkey -e/-v` keymap switch is not a bind).
_fa_parse_zsh() {
  awk '
    { sub(/[ \t]+#.*$/, "") }
    /^[ \t]*bindkey[ \t]/ {
      m = "main"; i = 2
      if ($2 == "-M") { m = $3; i = 4 }
      if ($i ~ /^-/ || NF < i + 1) next
      s = $i; gsub(/^[\x27"]|[\x27"]$/, "", s)
      printf "zsh\t%s\t%s %s\n", s, m, $(i + 1)
    }' "$@"
}
# fa_binds_parse <src> <file…>
fa_binds_parse() {
  local src="$1"; shift
  case "$src" in
    niri) _fa_parse_niri "$@" ;;
    hyprland) _fa_parse_hyprland "$@" ;;
    kde) _fa_parse_kde "$@" ;;
    nvim) _fa_parse_nvim "$@" ;;
    kitty) _fa_parse_kitty "$@" ;;
    zsh) _fa_parse_zsh "$@" ;;
    *) echo "feature-audit: no bind parser for '$src'" >&2; return 1 ;;
  esac
}

fa_binds_rows() {
  local -a files; mapfile -t files < <(_fa_binds_files "$1")
  if ((${#files[@]} == 0)); then
    echo "feature-audit: no config for '$1'" >&2; return 1
  fi
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
  if [[ -f "$exp" ]] && ! ej="$(jsonc_strip "$exp" | jq -c . 2>/dev/null)"; then
    echo "feature-audit: $exp is not valid JSONC" >&2; return 1
  fi
  jq -R -c --argjson e "$ej" \
    -f "$INSTALLER_DIR/lib/feature-audit/binds-plan.jq" <<<"$rows"
}

fa_binds_untested() {
  fa_binds_plan "$@" | jq -r 'select(.effect == null)
    | "\(.source)\t\(.chord)\t\(.action)"'
}

# fa_binds_program_sources <program> — bind sources a program's probe drives.
fa_binds_program_sources() {
  local s o
  for s in $(fa_binds_sources); do
    o="$(_fa_binds_field "$s" 3)"
    [[ "$o" == .installer/programs/*/"$1" \
       && "$(fa_binds_session "$s")" == - ]] && printf '%s\n' "$s"
  done
  return 0
}
