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
#         "settle": <seconds>  // wait before judging (default 1.5)
#       } ] }
# A chord match wins over an action glob; `{arg}` is the action's argument,
# `{num}` its first number.
#
# Public API:
#   feature_audit_binds_sources                 → registered source ids
#   feature_audit_binds_parse <source> <file…>
#       → rows from the given config files
#   feature_audit_binds_rows <src>              → rows from the shipped config
#   feature_audit_binds_expect_file <source>
#       → the source's audit-binds.jsonc path
#   feature_audit_binds_plan <source> [files… binds-file]
#       → one JSON object per row
#   feature_audit_binds_untested <source> [files… binds-file]
#       → rows lacking an expectation
#
# Used by: tools/feature-audit.sh, lib/feature-audit/{check,live-keybinds}.sh.
# =============================================================================

FA_REPO_ROOT="${FA_REPO_ROOT:-$(cd "$INSTALLER_DIR/.." && pwd)}"

# Registry: source → "session|config|owner" (repo-relative). The owner dir
# holds the source's audit-binds.jsonc. A compositor source (session set)
# runs in the keybinds phase; a program source (session `-`) is staged to
# that program's probe as `binds-plan.jsonl` and driven by it; session `*` is
# an app bind sent as real input in the first compositor session.
# `find:<dir>:<name>` walks a tree.
_X=.installer/extras/desktop _P=.installer/programs
declare -gA FA_BIND_SOURCES=(  # readability-ok: FA_ is the frozen env namespace
  [niri]="niri|.config/niri/conf.d/*.kdl|$_X/niri"
  [hyprland]="hyprland|.config/hypr/conf.d/*.lua|$_X/hyprland"
  [umbriel]="umbriel|.config/umbriel/conf.d/*.toml|$_X/umbriel"
  [kde]="kde|$_X/kde/skel/.config/kglobalshortcutsrc|$_X/kde"
  [nvim]="-|find:$_P/dev/nvim/home/.config/nvim:*.lua|$_P/dev/nvim"
  [kitty]="*|$_P/system/kitty/home/.config/kitty/conf/*.conf|$_P/system/kitty"
  [zsh]="-|find:$_P/system/zsh/home:.z*|$_P/system/zsh"
  [emacs]="-|$_P/dev/emacs/home/.config/doom/config.el|$_P/dev/emacs"
)
unset _X _P

feature_audit_binds_sources() { printf '%s\n' "${!FA_BIND_SOURCES[@]}" | sort; }

_binds_field() {
  local spec="${FA_BIND_SOURCES[$1]:-}"
  [[ -n "$spec" ]] || return 1
  # The spec's <n>th |-separated field.
  printf '%s\n' "$spec" | cut -d'|' -f"$2"
}

feature_audit_binds_session() { _binds_field "$1" 1; }

feature_audit_binds_expect_file() {
  printf '%s/%s/audit-binds.jsonc\n' "$FA_REPO_ROOT" \
    "$(_binds_field "$1" 3)"
}

# _binds_files <src> — the shipped config files for a source.
_binds_files() {
  local file_globs; file_globs="$(_binds_field "$1" 2)" || return 1
  if [[ "$file_globs" == find:* ]]; then
    local directory name
    # find:<dir>:<name-glob> — the directory and the glob after "find:".
    directory="$(printf '%s\n' "${file_globs:5}" | cut -d: -f1)"
    name="$(printf '%s\n' "${file_globs:5}" | cut -d: -f2-)"
    find "$FA_REPO_ROOT/$directory" -name "$name" -type f | sort
    return
  fi
  # shellcheck disable=SC2086 # intentional glob expansion
  ls -1 "$FA_REPO_ROOT"/$file_globs 2>/dev/null
}

# _binds_parse_niri <file…> — KDL `binds { Chord [props] { action; } }` blocks.
_binds_parse_niri() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-niri.awk" "$@"
}

# _binds_parse_umbriel <file…> — TOML `[keybinds]` (ADR 0159): a plain
# `"chord" = "action"`, an inline `{ action = "…", … }`, or a
# `[keybinds."chord"]` sub-table whose `action` key holds it.
_binds_parse_umbriel() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-umbriel.awk" "$@"
}

# _binds_parse_hyprland <file…> — Lua `hl.bind(<key expr>, hl.dsp.<disp>(…))`:
# string locals, `..` concatenation and `for i = a, b do … end` are evaluated
# (a static read of what the compositor would register).
_binds_parse_hyprland() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-hyprland.awk" "$@"
}

# _binds_parse_kde <kglobalshortcutsrc…> — `Action=Active\tAlt,Default,Label`
# per [component]; every active shortcut (not `none`) is a row.
_binds_parse_kde() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-kde.awk" "$@"
}

# _binds_parse_nvim <lua…> — see binds-nvim.awk.
_binds_parse_nvim() {
  local file
  for file in "$@"; do
    awk -f "$INSTALLER_DIR/lib/feature-audit/binds-nvim.awk" "$file"
  done
}

# _binds_parse_emacs <el…> — Doom map! forms; see binds-emacs.awk.
_binds_parse_emacs() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-emacs.awk" "$@"
}

# _binds_parse_kitty <conf…> — `map <keys> <action>`; kitty_mod is ctrl+shift
# (kitty's default; the curated config does not rebind it).
_binds_parse_kitty() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-kitty.awk" "$@"
}

# _binds_parse_zsh <rc…> — explicit `bindkey [-M map] <seq> <widget>` lines
# (a bare `bindkey -e/-v` keymap switch is not a bind).
_binds_parse_zsh() {
  awk -f "$INSTALLER_DIR/lib/feature-audit/binds-zsh.awk" "$@"
}
# feature_audit_binds_parse <src> <file…>
feature_audit_binds_parse() {
  local source_name="$1"; shift
  case "$source_name" in
    niri) _binds_parse_niri "$@" ;;
    hyprland) _binds_parse_hyprland "$@" ;;
    umbriel) _binds_parse_umbriel "$@" ;;
    kde) _binds_parse_kde "$@" ;;
    nvim) _binds_parse_nvim "$@" ;;
    emacs) _binds_parse_emacs "$@" ;;
    kitty) _binds_parse_kitty "$@" ;;
    zsh) _binds_parse_zsh "$@" ;;
    *) echo "feature-audit: no bind parser for '$source_name'" >&2; return 1 ;;
  esac
}

feature_audit_binds_rows() {
  local -a files; mapfile -t files < <(_binds_files "$1")
  if ((${#files[@]} == 0)); then
    echo "feature-audit: no config for '$1'" >&2; return 1
  fi
  feature_audit_binds_parse "$1" "${files[@]}"
}

# feature_audit_binds_plan <src> [config-file… expectations-file] — the matched
# plan.
feature_audit_binds_plan() {
  local source_name="$1"; shift
  local rows expected
  if (($#)); then
    expected="${*: -1}"
    rows="$(feature_audit_binds_parse "$source_name" "${@:1:$#-1}")" || return 1
  else
    expected="$(feature_audit_binds_expect_file "$source_name")"
    rows="$(feature_audit_binds_rows "$source_name")" || return 1
  fi
  local expect_json='{"expect":[]}'
  # The expectations file exists, and is not valid JSONC.
  if [[ -f "$expected" ]] \
    && ! expect_json="$(jsonc_strip "$expected" | jq -c . 2>/dev/null)"; then
    echo "feature-audit: $expected is not valid JSONC" >&2; return 1
  fi
  # Each row matched to its expectation.
  printf '%s\n' "$rows" | jq -R -c --argjson e "$expect_json" \
    -f "$INSTALLER_DIR/lib/feature-audit/binds-plan.jq"
}

feature_audit_binds_untested() {
  local untested='select(.effect == null) | "\(.source)\t\(.chord)\t\(.action)"'
  # The binds with no expectation, as source<TAB>chord<TAB>action.
  feature_audit_binds_plan "$@" | jq -r "$untested"
}

# feature_audit_binds_program_sources <program> — bind sources a program's probe
# drives.
feature_audit_binds_program_sources() {
  local source_name owner
  for source_name in $(feature_audit_binds_sources); do
    owner="$(_binds_field "$source_name" 3)"
    [[ "$owner" == .installer/programs/*/"$1" \
       && "$(feature_audit_binds_session "$source_name")" == - ]] \
       && printf '%s\n' "$source_name"
  done
  return 0
}
