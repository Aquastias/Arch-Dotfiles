# shellcheck shell=bash
# shellcheck disable=SC2016 # sh -c bodies expand in the child shell
# Feature Audit probe for nix (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package nix nix || return 0
if feature_audit_as_root; then
  feature_audit_check nix-daemon "nix-daemon.service enabled" \
    systemctl is-enabled --quiet nix-daemon.service
  feature_audit_check nix-store "/nix/store exists" test -d /nix/store
  return 0
fi
feature_audit_check nix-eval "nix evaluates as the user" \
  sh -c '[ "$(nix-instantiate --eval -E "1 + 1")" = 2 ]'
if feature_audit_installed nixd; then
  feature_audit_check nixd-eval "nixd's evaluator worker starts" \
    sh -c 'timeout 10 /usr/libexec/nixd-attrset-eval </dev/null'
fi
