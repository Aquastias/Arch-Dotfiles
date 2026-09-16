#!/usr/bin/env bash
# =============================================================================
# PROTOTYPE — throwaway. NOT the real statusline. Wipe me.
# =============================================================================
# Answers ONE design question: how should the redesigned Claude statusbar look
# in *your* terminal? Renders fixed mock states — no JSON stdin, no git, no
# persistence. Every value is hardcoded per scenario.
#
# Nerd glyphs are PUA codepoints, which get stripped if written as literals, so
# they're emitted via $'\uXXXX' escapes. Standard-Unicode emoji are literals.
#
# Run BOTH and pick the icon set:
#   bash .scratch/claude-statusline-prototype.sh emoji   # default
#   bash .scratch/claude-statusline-prototype.sh nerd
# =============================================================================

ICONSET="${1:-emoji}"

# --- ANSI-16 (theme-tracking; kitty remaps these) ----------------------------
C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'
DIM=$'\033[2m'; BOLD=$'\033[1m'; X=$'\033[0m'
SEP="${DIM}│${X}"

# --- Icon sets ---------------------------------------------------------------
if [ "$ICONSET" = nerd ]; then
  # PUA via escapes. Branch = U+E0A0, the exact glyph p10k renders (mode=powerline).
  G_DIR=$''; G_BR=$''; G_SHON=$''; G_SHOFF=$''
  G_PLAN=$''; G_CACHE=$''; G_5H=$''; G_CLK=$''
else
  ICONSET=emoji
  G_DIR='📁'; G_BR='🌿'; G_SHON='🛡'; G_SHOFF='🔓'
  G_PLAN='💼'; G_CACHE='💾'; G_5H='📊'; G_CLK='⏱'
fi
DOT="●"  # dirty-tree indicator (standard Unicode, always renders)

bar() { # $1 pct -> colored 10-cell bar
  local p=$1 f=$((${1}/10)) e c
  e=$((10-f))
  if   [ "$p" -ge 90 ]; then c=$R
  elif [ "$p" -ge 70 ]; then c=$Y
  else c=$G; fi
  local fill pad; printf -v fill "%${f}s"; printf -v pad "%${e}s"
  printf '%s%s%s%s' "$c" "${fill// /█}" "${pad// /░}" "$X"
}
cache_col() { [ "$1" -ge 90 ] && echo "$G" || { [ "$1" -ge 50 ] && echo "$Y" || echo "$R"; }; }
r5h_col()   { [ "$1" -ge 80 ] && echo "$R" || { [ "$1" -ge 50 ] && echo "$Y" || echo "$G"; }; }

render() {
  local dot_seg="" sb pl cc rc third
  # FIX: space between branch name and the red dot; only shown when dirty.
  [ "$DIRTY" = 1 ] && dot_seg=" ${R}${DOT}${X}"
  if [ "$SANDBOX" = on ]; then sb="${G}${G_SHON} sandbox${X}"
  else sb="${R}${G_SHOFF} no sandbox${X}"; fi
  pl="${C}${G_PLAN} ${PLAN}${X}"
  cc=$(cache_col "$CACHE")

  if [ "$BILLING" = api ]; then
    third="${Y}\$${COST}${X}"
  else
    rc=$(r5h_col "$R5PCT")
    third="${G_5H} ${rc}5h ${R5PCT}%${X} ${DIM}·${R5RESET}${X}"
  fi

  # line 1
  printf '%s[%s%s·%s%s]%s %s %s  %s %s%s  %s %s  %s\n' \
    "$C" "$BOLD" "$MODEL" "$EFFORT" "$X$C" "$X" \
    "$G_DIR" "$DIR" "$G_BR" "$BRANCH" "$dot_seg" "$SEP" "$sb" "$pl"
  # line 2  (FIX: added green, deleted red — split, not one green blob)
  printf '%s %s%% %s· %s/%s tok%s %s %s %s%%%s  %s %s  %s %s · %s+%s%s/%s-%s%s\n' \
    "$(bar "$PCT")" "$PCT" "$DIM" "$USED" "$WIN" "$X" \
    "$SEP" "${cc}${G_CACHE}" "$CACHE" "$X" \
    "$third" "$SEP" "$G_CLK" "$DUR" "$G" "$PLUS" "$X" "$R" "$MINUS" "$X"
  echo
}

hr() { printf '%s%s%s\n' "$DIM" "──────────────────────────────────────────────" "$X"; }

echo
echo "${BOLD}Claude statusbar prototype${X}  ${DIM}icon set: ${ICONSET}${X}"
hr

echo "${DIM}1) clean · low usage · Max sub${X}"
MODEL=Opus EFFORT=high DIR=dotfiles BRANCH=main DIRTY=0 SANDBOX=on \
PLAN="Max 20x" PCT=38 USED=76k WIN=200k CACHE=94 R5PCT=42 R5RESET="3h12m" \
DUR="12m 3s" PLUS=120 MINUS=30 BILLING=sub; render

echo "${DIM}2) DIRTY · high context · 5h filling${X}"
MODEL=Opus EFFORT=high DIR=Projects BRANCH=feat/statusline DIRTY=1 SANDBOX=on \
PLAN="Max 20x" PCT=78 USED=156k WIN=200k CACHE=61 R5PCT=74 R5RESET="1h04m" \
DUR="48m 9s" PLUS=980 MINUS=210 BILLING=sub; render

echo "${DIM}3) near limits · sandbox OFF · cache cold${X}"
MODEL=Sonnet EFFORT=medium DIR=eterniox BRANCH=main DIRTY=1 SANDBOX=off \
PLAN="Max 20x" PCT=93 USED=186k WIN=200k CACHE=28 R5PCT=91 R5RESET="22m" \
DUR="2h1m" PLUS=40 MINUS=15 BILLING=sub; render

echo "${DIM}4) API plan → \$cost replaces 5h meter${X}"
MODEL=Opus EFFORT=high DIR=dotfiles BRANCH=main DIRTY=0 SANDBOX=on \
PLAN="API" PCT=22 USED=44k WIN=200k CACHE=88 COST="1.37" \
DUR="5m 2s" PLUS=60 MINUS=8 BILLING=api; render

hr
echo "${DIM}legend:${X} ${G_DIR}dir ${G_BR}branch ${R}${DOT}${X}dirty ${G_SHON}sandbox ${G_PLAN}plan ${G_CACHE}cache ${G_5H}5h ${G_CLK}time"
[ "$ICONSET" = nerd ] && echo "${DIM}box/□ = your font lacks that codepoint; tell me and I'll swap it.${X}"
echo
