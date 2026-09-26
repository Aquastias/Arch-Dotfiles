#!/usr/bin/env bats
# verify.aur_audit (ADR 0143) is opt-in per VM test profile: on for the
# desktop profile (env/kde, the one with the most AUR packages), off for
# every other profile by default.

@test "aur_audit: on for the desktop VM profile, off elsewhere" {
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local f on=""
  while IFS= read -r f; do
    [[ "$(jsonc_strip "$f" | jq -r '.verify.aur_audit // false')" == true ]] \
      && on+=" ${f#"$BATS_TEST_DIRNAME/profiles/"}"
  done < <(find "$BATS_TEST_DIRNAME/profiles" -name '*.jsonc' | sort)
  [ "$on" = " env/kde.jsonc" ] || { echo "aur_audit on in:$on"; return 1; }
}
