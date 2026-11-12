#!/usr/bin/env bats
# Tests: the Umbriel derived sets (ADR 0159) — split from
# resolver-derived-sets.bats; shared setup in resolver-helpers.bash.

load resolver-helpers

@test "umbriel-shell set reports the Umbriel repo core packages" {
  source "$INSTALLER_DIR/lib/packages/umbriel.sh"
  local got want
  got="$(packages_of '{"users":[],"environment":{"desktop":["umbriel"],"stock":false}}' umbriel-shell)"
  want="$(umbriel_core_packages | sort)"
  [ "$got" == "$want" ]
}

@test "umbriel-aur set reports the AUR compositor and its portal" {
  local got
  got="$(packages_of '{"users":[],"environment":{"desktop":["umbriel"],"stock":true}}' umbriel-aur)"
  text_has_line "$got" umbriel-git
  text_has_line "$got" xdg-desktop-portal-umbriel-git
}

@test "umbriel sets are empty when Umbriel is not selected" {
  local config='{"users":[],"environment":{"desktop":["niri"],"stock":false}}'
  [ -z "$(packages_of "$config" umbriel-shell)" ]
  [ -z "$(packages_of "$config" umbriel-aur)" ]
}

@test "noctalia set reports the work preset on a Noctalia Umbriel box" {
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["umbriel"],"stock":false}}' noctalia)"
  text_has_line "$noctalia_packages" noctalia
}

@test "noctalia set is empty for stock Umbriel" {
  [ -z "$(packages_of '{"users":[],"environment":{"desktop":["umbriel"],"stock":true}}' noctalia)" ]
}
