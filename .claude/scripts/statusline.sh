#!/bin/bash
# Claude Code statusline (ADR 0133). Reads the status-line JSON payload on stdin
# and renders two lines. Colours are ANSI-16 so they track the terminal theme
# (ADR 0132). Cache-hit and 5-hour usage come from native payload fields; the
# ccusage burn detail is refreshed in the background into a cache so the render
# never blocks the prompt.
input=$(cat)

j() { jq -r "$1" <<<"$input" 2>/dev/null; }

MODEL=$(j '.model.display_name // "?"')
EFFORT=$(j '.effort.level // ""')
DIR=$(j '.workspace.current_dir // .cwd // ""')
PCT=$(j '.context_window.used_percentage // 0' | cut -d. -f1)
USED=$(j '.context_window.total_input_tokens // 0')
WINDOW=$(j '.context_window.context_window_size // 0')
CACHE_RATIO=$(j '.prompt_cache.hit_ratio // empty')
R5_PCT=$(j '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
R5_RESET=$(j '.rate_limits.five_hour.resets_at // empty')
COST=$(j '.cost.total_cost_usd // 0')
DURATION_MS=$(j '.cost.total_duration_ms // 0')
LINES_ADD=$(j '.cost.total_lines_added // 0')
LINES_DEL=$(j '.cost.total_lines_removed // 0')

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
SEP=" ${DIM}|${RESET} "

# Emoji icon set (ADR 0133: the nerd-glyph swap was rejected at prototype).
E_DIR='📁'; E_BR='🌿'; E_SHON='🛡'; E_SHOFF='🔓'
E_PLAN='💼'; E_CACHE='💾'; E_5H='📊'; E_BURN='🔥'; E_CLK='⏱'; DOT='●'

# 1234 → 1.2k, 200000 → 200k, 1500000 → 1.5M (no trailing .0).
fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    div = 1; suf = "";
    if (n >= 1000000) { div = 1000000; suf = "M" }
    else if (n >= 1000) { div = 1000; suf = "k" }
    v = n / div;
    if (v == int(v)) printf "%d%s", v, suf; else printf "%.1f%s", v, suf;
  }'
}

# seconds → "3h12m" / "22m"
fmt_dur_secs() {
  local s=$1 h m
  [ "$s" -lt 0 ] && s=0
  h=$((s / 3600)); m=$(((s % 3600) / 60))
  if [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"; else printf '%dm' "$m"; fi
}

# Context bar, coloured by fullness.
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi
FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

# Tokens used / window.
TOKENS_SEG=""
if [ "${WINDOW:-0}" -gt 0 ] 2>/dev/null; then
  TOKENS_SEG=" ${DIM}· $(fmt_tokens "$USED")/$(fmt_tokens "$WINDOW") tok${RESET}"
fi

# Cache-hit rate — native prompt_cache.hit_ratio (replaces the old transcript
# tail). Green efficient, red poor.
CACHE_SEG=""
if [ -n "$CACHE_RATIO" ]; then
  HIT=$(awk -v r="$CACHE_RATIO" 'BEGIN{printf "%d", r*100}')
  if [ "$HIT" -ge 90 ]; then CC="$GREEN"
  elif [ "$HIT" -ge 50 ]; then CC="$YELLOW"
  else CC="$RED"; fi
  CACHE_SEG="${SEP}${CC}${E_CACHE} ${HIT}%${RESET}"
fi

# Duration.
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

# Branch + dirty-tree dot (red ● when the working tree has changes).
BRANCH_SEG=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  BR=$(git branch --show-current 2>/dev/null)
  DIRTY=""
  [ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=" ${RED}${DOT}${RESET}"
  BRANCH_SEG=" ${E_BR} ${BR}${DIRTY}"
fi

# Sandbox status.
if [ "${SANDBOX_RUNTIME:-}" = "1" ] ||
   [ "$(jq -r '.sandbox.enabled // false' "$HOME/.claude/settings.json" 2>/dev/null)" = "true" ]; then
  SANDBOX_SEG="${GREEN}${E_SHON} sandbox${RESET}"
else
  SANDBOX_SEG="${RED}${E_SHOFF} no sandbox${RESET}"
fi

# Plan (subscriptionType + Max tier), falling back to billingType for API.
BILLING=$(grep -oE '"billingType" *: *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | head -1 | cut -d'"' -f4)
PLAN=""; CREDS="$HOME/.claude/.credentials.json"
if [ -f "$CREDS" ]; then
  read -r SUBTYPE RLTIER <<<"$(jq -r '.claudeAiOauth | "\(.subscriptionType // "-") \(.rateLimitTier // "-")"' "$CREDS" 2>/dev/null)"
  case "$SUBTYPE" in
    max) case "$RLTIER" in
        *max_20x) PLAN="Max 20x" ;; *max_5x) PLAN="Max 5x" ;; *) PLAN="Max" ;;
      esac ;;
    pro) PLAN="Pro" ;; free) PLAN="Free" ;; team) PLAN="Team" ;;
    enterprise) PLAN="Enterprise" ;; ""|"-") ;; *) PLAN="$SUBTYPE" ;;
  esac
fi
if [ -z "$PLAN" ]; then
  case "$BILLING" in *subscription*) PLAN="Subscription" ;; "") ;; *) PLAN="API" ;; esac
fi
PLAN_SEG=""; [ -n "$PLAN" ] && PLAN_SEG="${SEP}${CYAN}${E_PLAN} ${PLAN}${RESET}"

# Is this a usage-billed (API/console) plan? Subscriptions don't bill per token.
IS_API=0
case "$BILLING" in ""|*subscription*) ;; *) IS_API=1 ;; esac
[ "$PLAN" = "API" ] && IS_API=1

# ccusage burn detail — refreshed in the BACKGROUND at most every 30s into a
# cache; the render only reads the cache, so it never blocks the prompt. Schema
# is parsed defensively: any failure leaves the segment empty (works without
# ccusage installed).
CCU_SEG=""
if command -v ccusage >/dev/null 2>&1; then
  CCU_CACHE="${TMPDIR:-/tmp}/claude-statusline-ccusage-$(id -u).json"
  NOW=$(date +%s)
  MT=$(stat -c %Y "$CCU_CACHE" 2>/dev/null || echo 0)
  if [ ! -s "$CCU_CACHE" ] || [ "$((NOW - MT))" -ge 30 ]; then
    ( ccusage blocks --active --json >"${CCU_CACHE}.tmp" 2>/dev/null &&
      mv "${CCU_CACHE}.tmp" "$CCU_CACHE" ) >/dev/null 2>&1 &
  fi
  if [ -s "$CCU_CACHE" ]; then
    CCU_COST=$(jq -r 'first(.blocks[]? | select(.isActive==true) | .costUSD) // empty' "$CCU_CACHE" 2>/dev/null)
    [ -n "$CCU_COST" ] && CCU_SEG="${SEP}${E_BURN} $(printf '$%.2f' "$CCU_COST")"
  fi
fi

# Third slot on line 2: on a subscription the 5-hour meter (+ ccusage burn); on
# an API plan the per-session $cost. The 5h meter colours high = bad.
THIRD_SEG=""
if [ "$IS_API" = 1 ]; then
  THIRD_SEG="${SEP}${YELLOW}$(printf '$%.2f' "$COST")${RESET}"
elif [ -n "$R5_PCT" ]; then
  if [ "$R5_PCT" -ge 80 ]; then R5C="$RED"
  elif [ "$R5_PCT" -ge 50 ]; then R5C="$YELLOW"
  else R5C="$GREEN"; fi
  RESET_TXT=""
  if [ -n "$R5_RESET" ]; then
    REM=$(( R5_RESET - $(date +%s) ))
    RESET_TXT=" ${DIM}·$(fmt_dur_secs "$REM")${RESET}"
  fi
  THIRD_SEG="${SEP}${R5C}${E_5H} 5h ${R5_PCT}%${RESET}${RESET_TXT}${CCU_SEG}"
fi

# Lines changed: green add / red delete.
LINES_SEG=""
if [ "${LINES_ADD:-0}" -gt 0 ] 2>/dev/null || [ "${LINES_DEL:-0}" -gt 0 ] 2>/dev/null; then
  LINES_SEG=" · ${GREEN}+${LINES_ADD}${RESET}/${RED}-${LINES_DEL}${RESET}"
fi

# Model + effort label.
MODEL_SEG="[${BOLD}${MODEL}${RESET}"
[ -n "$EFFORT" ] && MODEL_SEG="${MODEL_SEG}${CYAN}·${EFFORT}${RESET}"
MODEL_SEG="${MODEL_SEG}]"

printf '%b\n' "${CYAN}${MODEL_SEG}${RESET} ${E_DIR} ${DIR##*/}${BRANCH_SEG}${SEP}${SANDBOX_SEG}${PLAN_SEG}"
printf '%b\n' "${BAR_COLOR}${BAR}${RESET} ${PCT}%${TOKENS_SEG}${CACHE_SEG}${THIRD_SEG}${SEP}${E_CLK} ${MINS}m ${SECS}s${LINES_SEG}"
