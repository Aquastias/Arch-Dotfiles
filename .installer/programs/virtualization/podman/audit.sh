# shellcheck shell=bash
# Feature Audit probe for podman (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package podman podman || return 0
feature_audit_as_user || return 0
feature_audit_check podman-subuid "subuid/subgid ranges for $FA_USER" \
  sh -c "grep -q '^$FA_USER:' /etc/subuid && grep -q '^$FA_USER:' /etc/subgid"
feature_audit_check podman-info "rootless podman info" podman info
[[ "$FA_ONLINE" == 1 ]] && feature_audit_check podman-run "rootless run hello-world" \
  podman run --rm docker.io/library/hello-world
