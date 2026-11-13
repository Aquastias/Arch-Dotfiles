#!/usr/bin/env bats
# verify.aur_audit (ADR 0143) is opt-in per VM test profile: on for the
# desktop profile (env/kde, the one with the most AUR packages), off for
# every other profile by default.

@test "aur_audit: on for the desktop VM profile, off elsewhere" {
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local profile_file on="" root="$BATS_TEST_DIRNAME/profiles/"
  while IFS= read -r profile_file; do
    # The profile turns the AUR audit on: note its path below the profiles.
    [[ "$(jsonc_strip "$profile_file" | jq -r '.verify.aur_audit // false')" == true ]] \
      && on+=" ${profile_file:${#root}}"
  done < <(find "$BATS_TEST_DIRNAME/profiles" -name '*.jsonc' | sort)
  [ "$on" = " env/kde.jsonc" ] || { echo "aur_audit on in:$on"; return 1; }
}
