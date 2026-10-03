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
