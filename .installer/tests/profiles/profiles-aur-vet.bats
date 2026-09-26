#!/usr/bin/env bats
# AUR Vetting in the Runner (ADR 0143): the vetter + data + seeded pin store
# land in the target before the AUR Helper bootstrap; each bootstrap rung
# vets its clone before makepkg; paru carries the PreBuildCommand hook; AUR
# builds refuse to run under yay.

setup() {
  T="$(mktemp -d)"
  export MOUNT_ROOT="$T/mnt"
  mkdir -p "$MOUNT_ROOT"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  sleep() { :; }
}

teardown() { rm -rf "$T"; }

# ── install into the target ─────────────────────────────────────────────────

@test "install: vetter, engine, data and seeded store land in the target" {
  _profiles_install_aur_vet
  [ -x "$MOUNT_ROOT/usr/local/bin/aur-vet" ]
  local f
  for f in scan.awk bump-only.awk rules.tsv indicators.tsv campaigns.tsv \
           sources.tsv; do
    [ -f "$MOUNT_ROOT/usr/local/share/aur-vet/$f" ]
  done
  cmp -s "$INSTALLER_DIR/aur/vetted.tsv" "$MOUNT_ROOT/etc/aur-vet/vetted.tsv"
  cmp -s "$INSTALLER_DIR/aur/allow.tsv" "$MOUNT_ROOT/etc/aur-vet/allow.tsv"
}

@test "install: the installed vetter finds its system data (no repo beside)" {
  _profiles_install_aur_vet
  run bash -c 'cd /tmp && "$1" --help' _ "$MOUNT_ROOT/usr/local/bin/aur-vet"
  [ "$status" -eq 0 ]
  run bash "$MOUNT_ROOT/usr/local/bin/aur-vet" nope
  [ "$status" -eq 2 ]
}

# ── bootstrap rung ──────────────────────────────────────────────────────────
# Runs the real rung script against fake su/getent/git/makepkg/aur-vet so the
# ordering and failure semantics are observed, not grepped.
_fake_rung_env() {
  BIN="$T/bin"; mkdir -p "$BIN" "$T/home"
  export CALLS="$T/calls" AV_RC="${1:-0}"; : > "$CALLS"
  printf '#!/bin/sh\necho "u:x:1000:1000::%s:/bin/bash"\n' "$T/home" \
    > "$BIN/getent"
  printf '#!/bin/sh\nshift 3\nexec bash -c "$1"\n' > "$BIN/su"
  printf '#!/bin/sh\necho "git $*" >> "$CALLS"\n%s\n' \
    'for a; do d="$a"; done; mkdir -p "$d"' > "$BIN/git"
  printf '#!/bin/sh\necho "makepkg $*" >> "$CALLS"\n' > "$BIN/makepkg"
  cat > "$BIN/aur-vet" <<'SH'
#!/bin/sh
echo "aur-vet UNATTENDED=$AUR_VET_UNATTENDED PKGBASE=$PKGBASE" >> "$CALLS"
exit "$AV_RC"
SH
  chmod +x "$BIN"/*
  export PATH="$BIN:$PATH" _PROFILES_AUR_VET_BIN="$BIN/aur-vet"
  arch-chroot() { shift; "$@"; }
}

@test "rung: vets the clone (unattended) before makepkg" {
  _fake_rung_env 0
  run _profiles_bootstrap_rung alice paru-bin
  [ "$status" -eq 0 ]
  [ "$(grep -n aur-vet "$CALLS" | cut -d: -f1)" -lt \
    "$(grep -n makepkg "$CALLS" | cut -d: -f1)" ]
  grep -q "aur-vet UNATTENDED=1 PKGBASE=paru-bin" "$CALLS"
}

@test "rung: a full clone, so a Vetted Commit diff is possible" {
  _fake_rung_env 0
  run _profiles_bootstrap_rung alice paru
  ! grep -q -- "--depth" "$CALLS"
}

@test "rung: a vetter abort fails the rung and never runs makepkg" {
  _fake_rung_env 1
  run _profiles_bootstrap_rung alice paru
  [ "$status" -ne 0 ]
  ! grep -q makepkg "$CALLS"
}

# ── AUR pass + helper policy ────────────────────────────────────────────────

@test "aur_install: yay is refused — vetting needs paru" {
  arch-chroot() { echo "$*" >> "$T/calls"; }
  run _profiles_aur_install alice yay pkg1
  [ "$status" -ne 0 ]
  [[ "$output" == *"vetting needs paru"* ]]
  [ ! -e "$T/calls" ]
}

@test "aur_install: paru runs unattended so the hook never prompts" {
  arch-chroot() { echo "$*" >> "$T/calls"; }
  _profiles_aur_install alice paru pkg1
  grep -q "AUR_VET_UNATTENDED=1 paru -S --noconfirm --needed pkg1" "$T/calls"
}

@test "userprog: under yay the helper is repo-only; under paru unchanged" {
  resolve_program() { echo "cat/prog"; }
  _profiles_userprog_chroot() { echo "$4" > "$T/helper"; }
  _profiles_install_user_program alice prog yay
  [ "$(< "$T/helper")" = "yay --repo" ]
  _profiles_install_user_program alice prog paru
  [ "$(< "$T/helper")" = "paru" ]
}

@test "userprog: program installs run the hook unattended" {
  resolve_program() { echo "cat/prog"; }
  arch-chroot() { cat > "$T/script"; }
  _profiles_install_user_program alice prog paru
  grep -q "export AUR_VET_UNATTENDED=1" "$T/script"
}

# ── paru hook wiring ────────────────────────────────────────────────────────

@test "paru.conf: the hook lands under [options], replacing any other" {
  printf '[options]\nBottomUp\n#PreBuildCommand = foo\n\n[bin]\nSudo = doas\n' \
    > "$T/paru.conf"
  _profiles_wire_paru_hook "$T/paru.conf"
  [ "$(grep -c PreBuildCommand "$T/paru.conf")" -eq 1 ]
  [ "$(sed -n 2p "$T/paru.conf")" = \
    "PreBuildCommand = /usr/local/bin/aur-vet" ]
  _profiles_wire_paru_hook "$T/paru.conf"
  [ "$(grep -c PreBuildCommand "$T/paru.conf")" -eq 1 ]
}

@test "paru.conf: a config without [options] gains one" {
  printf '[bin]\nSudo = doas\n' > "$T/paru.conf"
  _profiles_wire_paru_hook "$T/paru.conf"
  grep -qx "PreBuildCommand = /usr/local/bin/aur-vet" "$T/paru.conf"
  grep -qx '\[options\]' "$T/paru.conf"
}

@test "paru.conf: every paru.conf shipped in the repo carries the hook" {
  local f bad=""
  while IFS= read -r f; do
    grep -qx 'PreBuildCommand = /usr/local/bin/aur-vet' "$INSTALLER_DIR/../$f" \
      || bad+=" $f"
  done < <(git -C "$INSTALLER_DIR" ls-files --full-name ':/*paru.conf')
  [ -z "$bad" ] || { echo "missing hook:$bad"; return 1; }
}

@test "install: the installed vetter ignores test-only env overrides" {
  _profiles_install_aur_vet
  mkdir -p "$T/fake-store"; : > "$T/fake-store/vetted.tsv"
  run env AUR_VET_STORE="$T/fake-store" AUR_VET_DATA="$T/nope" \
    bash -c 'cd /tmp && "$1" export --check "$2"' _ \
    "$MOUNT_ROOT/usr/local/bin/aur-vet" "$T/fake-store"
  [[ "$output" == *"/etc/aur-vet and"* ]]   # the system store, not ours
}

@test "paru.conf: a missing system paru.conf is created with the hook" {
  _profiles_wire_paru_hook "$T/etc-paru.conf" create
  grep -qx "PreBuildCommand = /usr/local/bin/aur-vet" "$T/etc-paru.conf"
}
