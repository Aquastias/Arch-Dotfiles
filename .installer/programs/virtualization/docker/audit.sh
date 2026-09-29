# shellcheck shell=bash
# Feature Audit probe for docker (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg docker docker || return 0
if fa_as_root; then
  fa_check docker-socket "docker.socket active" fa_unit_active docker.socket
  return 0
fi
if ! id -nG | grep -qw docker; then
  fa_skip docker-user "$FA_USER not in docker"; return 0
fi
fa_check docker-info "daemon reachable as a docker-group user" docker info
# pulling an image is inherently online, so it runs only online
[[ "$FA_ONLINE" == 1 ]] && fa_check docker-run "docker run hello-world" \
  docker run --rm hello-world
fa_check docker-compose "compose plugin present" docker compose version
