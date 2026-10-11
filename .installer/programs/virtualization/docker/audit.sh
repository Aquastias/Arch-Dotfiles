# shellcheck shell=bash
# Feature Audit probe for docker (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package docker docker || return 0
if feature_audit_as_root; then
  feature_audit_check docker-socket "docker.socket active" feature_audit_unit_active docker.socket
  return 0
fi
if ! id -nG | grep -qw docker; then
  feature_audit_skip docker-user "$FA_USER not in docker"; return 0
fi
feature_audit_check docker-info "daemon reachable as a docker-group user" docker info
# pulling an image is inherently online, so it runs only online
[[ "$FA_ONLINE" == 1 ]] && feature_audit_check docker-run "docker run hello-world" \
  docker run --rm hello-world
feature_audit_check docker-compose "compose plugin present" docker compose version
