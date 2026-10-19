#!/usr/bin/env bash
# =============================================================================
# lib/config/display.sh — Display Label formatter
# =============================================================================
# Turns a raw menu token into its human-facing Display Label. DISPLAY ONLY —
# the result is never stored in the Config State; callers format at the render
# boundary and reverse-map on the way back in.
#
# Rules (see PRD guided-installer-legion-fixes):
#   1. A curated table gives acronyms / proper names their exact casing
#      (KDE, NVIDIA, ZFS, SSH, ESP, systemd-boot, EFISTUB, rEFInd, …).
#   2. Otherwise the string is sentence-cased: the first letter is upper-cased,
#      any curated acronym WORD is upper-cased, remaining words are lower-cased
#      (e.g. "esp size" → "ESP size", "age key url" → "Age key URL").
#   3. Unknown single tokens fall back to plain first-letter-uppercase, so the
#      curated table never has to be exhaustive.
#   4. Technical / free-text tokens pass through unchanged: anything containing
#      / = : . , a digit, or starting with a non-letter (/dev/sda,
#      en_US.UTF-8, key=value, a typed hostname like legion5, 2G).
#
# Used by: lib/config/environment.sh, lib/guided/controller.sh.
# =============================================================================

# _display_curated <token> → the curated Display Label for <token> (matched
# case-insensitively), or non-zero when <token> has no curated entry.
_display_curated() {
  case "${1,,}" in
  kde)          echo KDE ;;
  hyprland)     echo Hyprland ;;
  niri)         echo niri ;;
  noctalia)     echo Noctalia ;;
  sddm)         echo SDDM ;;
  greetd)       echo "greetd (tuigreet)" ;;
  noctalia-greeter) echo "Noctalia Greeter" ;;
  gpu)          echo GPU ;;
  ssh)          echo SSH ;;
  zfs)          echo ZFS ;;
  ufw)          echo UFW ;;
  lts)          echo LTS ;;
  url)          echo URL ;;
  esp)          echo ESP ;;
  amd)          echo AMD ;;
  nvidia)       echo NVIDIA ;;
  ext4)         echo Ext4 ;;
  xfs)          echo Xfs ;;
  btrfs)        echo Btrfs ;;
  systemd-boot) echo systemd-boot ;;
  efistub)      echo EFISTUB ;;
  refind)       echo rEFInd ;;
  *)            return 1 ;;
  esac
}

# _display_passthrough <token> → 0 when the token is technical / free-text and
# must be shown verbatim.
_display_passthrough() {
  local token="$1"
  [[ -z "$token" ]]              && return 0
  [[ "$token" == *[/=:.]* ]]     && return 0
  [[ "$token" == *[0-9]* ]]      && return 0
  [[ "$token" == [!A-Za-z]* ]]   && return 0
  return 1
}

# _display_word <word> → the word's display form: curated acronym, else
# first-letter-uppercase with the rest lower-cased. Assumes a single word.
_display_word() {
  local curated lower
  if curated="$(_display_curated "$1")"; then printf '%s' "$curated"; return; fi
  lower="${1,,}"
  printf '%s' "${lower^}"
}

# display_label <token> → the Display Label for <token>. See file header.
display_label() {
  local token="$1" curated
  # Whole-token curated first (covers hyphenated names like systemd-boot).
  if curated="$(_display_curated "$token")"; then
    printf '%s\n' "$curated"
    return
  fi
  if _display_passthrough "$token"; then printf '%s\n' "$token"; return; fi

  local -a words; read -ra words <<<"$token"
  local out="" i word display_word
  for i in "${!words[@]}"; do
    word="${words[$i]}"
    if display_word="$(_display_curated "$word")"; then
      : # curated acronym word (ESP, URL, ZFS, …) — keep as-is
    elif [[ "$i" -eq 0 ]]; then
      display_word="$(_display_word "$word")"        # first word
    else
      display_word="${word,,}"                       # rest: lower
    fi
    out+="${out:+ }$display_word"
  done
  printf '%s\n' "$out"
}

# display_reverse <displayed> <raw-candidate>... → the raw candidate whose
# display_label equals <displayed> (first match). Non-zero + no output when no
# candidate matches. The format-aware inverse used by the controller's reverse
# lookups so a re-cased row still resolves to its stored value.
display_reverse() {
  local want="$1" candidate; shift
  for candidate in "$@"; do
    [[ "$(display_label "$candidate")" == "$want" ]] \
      && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}
