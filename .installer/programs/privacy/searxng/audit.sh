# shellcheck shell=bash
# Feature Audit probe for searxng (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg searxng podman || return 0
fa_as_user || return 0
[[ -f "$FA_HOME/.config/searxng/settings.yml" ]] \
  || { fa_skip searxng-user "not seeded for $FA_USER"; return 0; }
fa_check searxng-linger "user linger enabled (starts at boot)" \
  test -e "/var/lib/systemd/linger/$FA_USER"
# the image is pulled on first online start (podman cannot pull in the
# chroot): offline before that pull, there is nothing to run yet
if [[ "${FA_ONLINE:-1}" == 0 ]] \
   && ! podman image exists docker.io/searxng/searxng:latest 2>/dev/null; then
  fa_skip searxng-unit "image not pulled yet (first online start fetches it)"
  return 0
fi
# timer-started 30s after the user manager, then a first pull: give it time
_fa_searxng_up() {
  local i
  for i in $(seq 60); do
    systemctl --user is-active --quiet searxng.service && return 0
    sleep 5
  done
  return 1
}
fa_check searxng-unit "searxng user unit comes up" _fa_searxng_up
fa_check searxng-http "answers on 127.0.0.1:8080" \
  curl -fsS -m 10 --retry 6 --retry-delay 5 --retry-all-errors \
  -o /dev/null http://127.0.0.1:8080/
