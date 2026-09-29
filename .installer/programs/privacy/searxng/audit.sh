# shellcheck shell=bash
# Feature Audit probe for searxng (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg searxng podman || return 0
fa_as_user || return 0
[[ -f "$FA_HOME/.config/searxng/settings.yml" ]] \
  || { fa_skip searxng-user "not seeded for $FA_USER"; return 0; }
fa_check searxng-linger "user linger enabled (starts at boot)" \
  test -e "/var/lib/systemd/linger/$FA_USER"
fa_check searxng-unit "searxng user unit active" \
  sh -c 'systemctl --user list-units --type=service --state=active \
    | grep -qi searx'
fa_check searxng-http "answers on 127.0.0.1:8080" \
  curl -fsS -m 10 -o /dev/null http://127.0.0.1:8080/
