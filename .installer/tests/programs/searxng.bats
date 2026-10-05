#!/usr/bin/env bats
# searxng's quadlet + settings (Audit Run 20261003): the limiter pointed at a
# `valkey` host no quadlet container is named, and the entrypoint tried to
# chown the :ro config mount. A private instance needs neither.

setup() {
  S="$BATS_TEST_DIRNAME/../../programs/privacy/searxng"
  Q="$S/home/.config/containers/systemd"
}

@test "private instance: no limiter, no valkey anywhere" {
  grep -qE '^\s*limiter: false' "$S/settings.yml"
  [ ! -e "$Q/valkey.container" ]
  [ -z "$(grep -rl valkey "$S")" ]
}

@test "config mount reads as the image's searxng user (no chown)" {
  grep -qx 'UserNS=keep-id:uid=977,gid=977' "$Q/searxng.container"
}

@test "Tor-only engines are removed (no Tor proxy)" {
  grep -q -- '- ahmia' "$S/settings.yml"
  grep -q -- '- torch' "$S/settings.yml"
}

@test "boot: waits for the network, allows a slow first pull, no warning" {
  # Audit Run 20261004: the masked network wait crash-looped searxng's
  # startup network check; the first pull outran the 90s start timeout.
  [ -z "$(grep -n 'podman-user-wait-network-online' "$S/install.sh" \
    | grep 'ln -s')" ]
  grep -qx 'TimeoutStartSec=900' "$Q/searxng.container"
  [ -f "$S/limiter.toml" ]
  grep -q 'limiter.toml' "$S/install.sh"
}

@test "an offline first start keeps retrying until the image can be pulled" {
  # kde-pure 20261004: three quick pull failures hit the start limit and
  # searxng never came up (a laptop booting before its Wi-Fi would too)
  grep -qx 'StartLimitIntervalSec=0' "$Q/searxng.container"
  grep -qx 'RestartSec=30' "$Q/searxng.container"
}

@test "network-online.target is pulled in for podman's user-level wait" {
  # Audit Run 20261004: on pure / services-off hosts no system service wants
  # the target, so the wait polled it until it timed out at every boot
  grep -q 'systemctl add-wants multi-user.target network-online.target' \
    "$S/install.sh"
}

@test "started by a user timer, never by default.target (no login stall)" {
  # Audit Run 20261004: NM wait-online is masked (base-services.sh), so a
  # default.target start pulled before the link was up; waiting in the unit
  # would hold the user manager's startup (and a login) instead
  ! grep -q 'WantedBy=default.target' "$Q/searxng.container"
  local t="$S/home/.config/systemd/user/searxng.timer"
  grep -qx 'OnStartupSec=30' "$t"
  grep -qx 'WantedBy=timers.target' "$t"
  grep -q 'timers.target.wants/searxng.timer' "$S/install.sh"
}
