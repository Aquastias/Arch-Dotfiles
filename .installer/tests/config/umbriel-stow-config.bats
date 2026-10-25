#!/usr/bin/env bats
# Tests: the curated Umbriel glue (ADR 0159) — split from
# noctalia-stow-config.bats; shared setup in noctalia-stow-helpers.bash.

load noctalia-stow-helpers

UMB="$BATS_TEST_DIRNAME/../../../.config/umbriel"

@test "umbriel config.toml is a manifest that includes the conf.d/ parts" {
  grep -q '"conf.d/autostart.toml",' "$UMB/config.toml"
  grep -q '"conf.d/input.toml",' "$UMB/config.toml"
  # every listed part ships
  local part
  for part in $(grep -o 'conf.d/[a-z]*\.toml' "$UMB/config.toml"); do
    [ -f "$UMB/$part" ] || { echo "missing $part"; return 1; }
  done
}

# Noctalia's umbriel template post-hook rewrites config.toml unless this line is
# already exactly so — through the stow link, into the repo.
@test "umbriel includes Noctalia's palette exactly as its post-hook writes it" {
  grep -A1 -x '\[include.optional\]' "$UMB/config.toml" \
    | grep -qx 'files = \["noctalia.toml"\]'
}

@test "umbriel autostarts Noctalia and the enable one-shot" {
  grep -qx '  "noctalia",' "$UMB/conf.d/autostart.toml"
  grep -q 'noctalia-enable-plugins' "$UMB/conf.d/autostart.toml"
}

@test "umbriel sets the Bibata Modern Ice cursor (ADR 0098)" {
  grep -qx 'theme = "Bibata-Modern-Ice"' "$UMB/conf.d/input.toml"
  grep -qx 'size = 24' "$UMB/conf.d/input.toml"
}

@test "umbriel is click-to-focus (ADR 0147)" {
  grep -qx 'follows_mouse = false' "$UMB/conf.d/input.toml"
}

@test "umbriel routes Qt through qt6ct (ADR 0102)" {
  grep -qx 'QT_QPA_PLATFORMTHEME = "qt6ct"' "$UMB/conf.d/environment.toml"
}

@test "umbriel seeds no hardcoded output (ADR 0110)" {
  run grep -rEq '^\[output' "$UMB"
  [ "$status" -ne 0 ]
}

@test "umbriel skips its cheatsheet so no welcome on first login" {
  grep -qx 'show_cheatsheet = false' "$UMB/conf.d/appearance.toml"
}
