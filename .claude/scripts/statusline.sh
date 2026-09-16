#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
# Tokens currently in context. current_usage is an OBJECT (per-component
# breakdown), so it can't be formatted as a number — use the scalar
# total_input_tokens, which is what used_percentage is computed from.
USED=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
WINDOW=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // ""')

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

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

# Pick bar color based on context usage
if [ "$PCT" -ge 90 ]; then
  BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then
  BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

FILLED=$((PCT / 10))
EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"
printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

# Tokens used / context window size (omitted if the window isn't reported).
TOKENS_SEG=""
if [ "${WINDOW:-0}" -gt 0 ] 2>/dev/null; then
  TOKENS_SEG=" ${DIM}· $(fmt_tokens "$USED")/$(fmt_tokens "$WINDOW") tok${RESET}"
fi

# Cache hit rate of the latest turn, read from the transcript's most recent
# usage line: cache_read / (cache_read + cache_creation + input). Not in the
# status-line payload, so we pull it from .transcript_path. Green = efficient.
CACHE_SEG=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  read -r CR CC IN <<<"$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
    | grep '"cache_read_input_tokens"' | tail -n1 \
    | jq -r '.message.usage
        | "\(.cache_read_input_tokens // 0) \(.cache_creation_input_tokens // 0) \(.input_tokens // 0)"' \
        2>/dev/null)"
  DENOM=$(( ${CR:-0} + ${CC:-0} + ${IN:-0} ))
  if [ "$DENOM" -gt 0 ]; then
    HIT=$(( ${CR:-0} * 100 / DENOM ))
    if [ "$HIT" -ge 90 ]; then CACHE_COLOR="$GREEN"
    elif [ "$HIT" -ge 50 ]; then CACHE_COLOR="$YELLOW"
    else CACHE_COLOR="$RED"; fi
    CACHE_SEG=" ${DIM}·${RESET} ${CACHE_COLOR}💾 ${HIT}%${RESET}"
  fi
fi

MINS=$((DURATION_MS / 60000))
SECS=$(((DURATION_MS % 60000) / 1000))

BRANCH=""
git rev-parse --git-dir >/dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"

# Sandbox status: SANDBOX_RUNTIME=1 in the env means the sandbox is active for
# this session; fall back to the configured setting if it isn't inherited.
if [ "${SANDBOX_RUNTIME:-}" = "1" ] ||
   [ "$(jq -r '.sandbox.enabled // false' "$HOME/.claude/settings.json" 2>/dev/null)" = "true" ]; then
  SANDBOX_SEG="${GREEN}🛡️ sandbox${RESET}"
else
  SANDBOX_SEG="${RED}🔓 no sandbox${RESET}"
fi

# API billing: only show the per-session $ cost on a usage-billed (API/console)
# plan. Subscriptions (Pro/Max — billingType *subscription*) don't bill per
# token, so the figure is noise there.
BILLING=$(grep -oE '"billingType" *: *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | head -1 | cut -d'"' -f4)
COST_SEG=""
case "$BILLING" in
  "" | *subscription*) ;;
  *) COST_SEG=" | ${YELLOW}$(printf '$%.2f' "$COST")${RESET}" ;;
esac

# Current plan. Authoritative source is the OAuth credentials' subscriptionType
# (+ rateLimitTier for the Max sub-tier); fall back to billingType for API
# accounts that have no Claude subscription.
PLAN=""
CREDS="$HOME/.claude/.credentials.json"
if [ -f "$CREDS" ]; then
  read -r SUBTYPE RLTIER <<<"$(jq -r '.claudeAiOauth | "\(.subscriptionType // "-") \(.rateLimitTier // "-")"' "$CREDS" 2>/dev/null)"
  case "$SUBTYPE" in
    max)
      case "$RLTIER" in
        *max_20x) PLAN="Max 20x" ;;
        *max_5x) PLAN="Max 5x" ;;
        *) PLAN="Max" ;;
      esac ;;
    pro) PLAN="Pro" ;;
    free) PLAN="Free" ;;
    team) PLAN="Team" ;;
    enterprise) PLAN="Enterprise" ;;
    "" | "-") ;;
    *) PLAN="$SUBTYPE" ;;
  esac
fi
if [ -z "$PLAN" ]; then
  case "$BILLING" in
    *subscription*) PLAN="Subscription" ;;
    "") ;;
    *) PLAN="API" ;;
  esac
fi
PLAN_SEG=""
[ -n "$PLAN" ] && PLAN_SEG=" | ${CYAN}💼 ${PLAN}${RESET}"

echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}$BRANCH | ${SANDBOX_SEG}${PLAN_SEG}"
echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT}%${TOKENS_SEG}${CACHE_SEG}${COST_SEG} | ⏱️ ${MINS}m ${SECS}s"
