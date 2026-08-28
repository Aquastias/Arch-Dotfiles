#!/usr/bin/env bats
# Tests for .installer/lib/config/fonts.sh — the Font Catalog resolver (ADR
# 0080): a
# pure helper turning options.fonts into the font packages that install, split
# by repo (pacstrap) vs AUR (paru pass), with the catalog's defaults applied
# when options.fonts is absent.
#
# Behaviour under test is external only (the decision the helper produces),
# never internal structure. Prior art: tests/config/printing.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error
  # shellcheck source=../../lib/config/fonts.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/fonts.sh"
}

# ── catalog + defaults ──────────────────────────────────────────────────────

@test "fonts_catalog_tokens: lists the full catalog incl. off-by-default" {
  run fonts_catalog_tokens
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx ttf-jetbrains-mono-nerd
  echo "$output" | grep -qx otf-monaspace-nerd   # off-by-default still offered
  echo "$output" | grep -qx ttf-sazanami
  echo "$output" | grep -qx ttf-firacode-nerd
}

@test "fonts_catalog_tokens: plain ttf-fira-code is dropped for the nerd build" {
  run fonts_catalog_tokens
  ! echo "$output" | grep -qx ttf-fira-code
}

@test "fonts_default_selection: the on-by-default set, without the off ones" {
  run fonts_default_selection
  echo "$output" | grep -qx noto-fonts
  echo "$output" | grep -qx noto-fonts-cjk
  echo "$output" | grep -qx ttf-ms-fonts
  echo "$output" | grep -qx ttf-firacode-nerd
  ! echo "$output" | grep -qx otf-monaspace-nerd
  ! echo "$output" | grep -qx ttf-sazanami
}

@test "fonts_default_selection_json: a JSON array of the default set" {
  run fonts_default_selection_json
  echo "$output" | jq -e 'type == "array" and (index("noto-fonts") != null)'
  echo "$output" | jq -e '(index("otf-monaspace-nerd")) == null'
}

# ── fonts_selected: absent ⇒ defaults; explicit wins; [] honoured ───────────

@test "fonts_selected: absent options.fonts yields the catalog defaults" {
  run fonts_selected '{}'
  echo "$output" | grep -qx noto-fonts
  ! echo "$output" | grep -qx otf-monaspace-nerd
}

@test "fonts_selected: an explicit selection is honoured verbatim" {
  run fonts_selected '{"options":{"fonts":["noto-fonts","otf-monaspace-nerd"]}}'
  [ "$output" = "noto-fonts"$'\n'"otf-monaspace-nerd" ]
}

@test "fonts_selected: an explicit empty array means no fonts" {
  run fonts_selected '{"options":{"fonts":[]}}'
  [ -z "$output" ]
}

# ── repo vs AUR routing ─────────────────────────────────────────────────────

@test "fonts_repo_packages: defaults route repo fonts, not ttf-ms-fonts" {
  run fonts_repo_packages '{}'
  echo "$output" | grep -qx noto-fonts
  echo "$output" | grep -qx ttf-firacode-nerd
  ! echo "$output" | grep -qx ttf-ms-fonts
}

@test "fonts_aur_packages: defaults route ttf-ms-fonts to the paru pass only" {
  run fonts_aur_packages '{}'
  [ "$output" = "ttf-ms-fonts" ]
}

@test "fonts_aur_packages: an all-repo selection yields nothing" {
  run fonts_aur_packages '{"options":{"fonts":["noto-fonts","ttf-dejavu"]}}'
  [ -z "$output" ]
}

@test "fonts_repo_packages: an authored/unknown font routes to repo (pacstrap)" {
  run fonts_repo_packages '{"options":{"fonts":["some-custom-font"]}}'
  [ "$output" = "some-custom-font" ]
}
