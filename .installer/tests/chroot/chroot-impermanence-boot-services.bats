#!/usr/bin/env bats
# Tests: boot services and enablements (split from chroot-impermanence.bats;
# shared setup in chroot-impermanence-helpers.bash)

load chroot-impermanence-helpers


# ── _impermanence_relocate_enablements ──────────────────────────────────────

@test "relocate: mirrors /etc enablements onto /usr/lib <target>.wants" {
  _seed_enablements
  _impermanence_relocate_enablements
  [ -L "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/NetworkManager.service" ]
  [ -L "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/sshd.service" ]
}

@test "relocate: mirrored wants symlink is relative (../<unit>)" {
  _seed_enablements
  _impermanence_relocate_enablements
  local link_target
  link_target="$(readlink "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/NetworkManager.service")"
  [ "$link_target" = "../NetworkManager.service" ]
}

@test "relocate: mirrors the display-manager.service alias onto /usr/lib" {
  _seed_enablements
  _impermanence_relocate_enablements
  [ -L "$FAKEROOT/usr/lib/systemd/system/display-manager.service" ]
  local link_target
  link_target="$(readlink "$FAKEROOT/usr/lib/systemd/system/display-manager.service")"
  [ "$link_target" = "/usr/lib/systemd/system/sddm.service" ]
}

@test "relocate: skips units that exist only under /etc (no dangling symlink)" {
  _seed_enablements
  _impermanence_relocate_enablements
  [ ! -e "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/custom.service" ]
  [ ! -L "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/custom.service" ]
}

@test "relocate: leaves the original /etc symlinks in place (copy, not move)" {
  _seed_enablements
  _impermanence_relocate_enablements
  [ -L "$FAKEROOT/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]
}

@test "relocate: runs as an impermanence_apply step" {
  _seed_enablements
  run_enabled
  [ -L "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/NetworkManager.service" ]
}


# ── DM login retained: no tty1 autologin, DM stays enabled (ADR 0061) ────────
# The tty1 autologin was removed; impermanence hosts get a real display-manager
# login. The relocate step (above) mirrors the DM enablement onto /usr/lib so it
# survives the rolled-back root; apply must not disable the DM or auto-log-in.

@test "no tty1 autologin function exists" {
  ! declare -F _impermanence_setup_autologin
}

@test "apply: does not disable the display manager" {
  _seed_enablements
  run_enabled
  ! grep -qE "disable sddm" "$CALLS"
}

@test "apply: writes no getty@tty1 autologin drop-in" {
  _seed_enablements
  run_enabled
  [ ! -f "$FAKEROOT/usr/lib/systemd/system/getty@tty1.service.d/autologin.conf" ]
}

@test "apply: writes no startplasma tty launcher" {
  _seed_enablements
  run_enabled
  [ ! -f "$FAKEROOT/etc/profile.d/zz-autostart-plasma.sh" ]
}

@test "apply: still mirrors the DM enablement onto /usr/lib (login survives)" {
  _seed_enablements
  run_enabled
  [ -L "$FAKEROOT/usr/lib/systemd/system/display-manager.service" ]
}


# ── boot user-linger service (login must not race a busy impermanent boot) ────

@test "graphical-fix: writes user@ boot-linger service for human users" {
  mkdir -p "$FAKEROOT/etc"
  printf 'root:x:0:0::/root:/bin/bash\naquastias:x:1000:1000::/home/aquastias:/bin/zsh\nnobody:x:65534:65534::/:/usr/bin/nologin\n' \
    > "$FAKEROOT/etc/passwd"
  _impermanence_graphical_session_fix
  local unit_file="$FAKEROOT/usr/lib/systemd/system/impermanence-user-linger.service"
  [ -f "$unit_file" ]
  grep -qF "loginctl enable-linger aquastias" "$unit_file"
  ! grep -qF "nobody" "$unit_file"
  [ -L "$FAKEROOT/usr/lib/systemd/system/multi-user.target.wants/impermanence-user-linger.service" ]
  [ -f "$FAKEROOT/var/lib/systemd/linger/aquastias" ]
}


# ── machine-id-commit skip (ADR 0144) ───────────────────────────────────────
# /etc/machine-id is a persist bind (a mount point), so the stock
# systemd-machine-id-commit.service runs and fails every boot ("not on a
# temporary file system"). A /usr drop-in skips it via a negated condition.

@test "enabled: drop-in skips systemd-machine-id-commit on the bound id" {
  run_enabled
  local dropin_directory="$FAKEROOT/usr/lib/systemd/system/systemd-machine-id-commit.service.d"
  grep -qxF "ConditionPathIsMountPoint=!/etc/machine-id" "$dropin_directory/impermanence.conf"
}

@test "disabled: no machine-id-commit drop-in" {
  export IMPERMANENCE_ENABLED=false
  impermanence_apply
  local unit_directory="$FAKEROOT/usr/lib/systemd/system"
  [ ! -e "$unit_directory/systemd-machine-id-commit.service.d" ]
}
