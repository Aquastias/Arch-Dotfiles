# shellcheck shell=bash
# Feature Audit probe for sops (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package sops sops || return 0
feature_audit_as_root || return 0
feature_audit_check sops-machine-key "Machine Age Key derived" \
  test -s /etc/secrets/age/keys.txt
_probe_sops_key() {
  ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key 2>/dev/null \
    | cmp -s - /etc/secrets/age/keys.txt
}
feature_audit_check sops-key-matches "age key derives from the SSH host key" _probe_sops_key
feature_audit_check sops-runtime "sops-runtime.service active" \
  feature_audit_unit_active sops-runtime
if compgen -G '/etc/secrets/sops/*.json' >/dev/null; then
  feature_audit_check sops-secrets "runtime secrets decrypted into /run/secrets" \
    sh -c 'ls /run/secrets/*.json >/dev/null 2>&1'
else
  feature_audit_skip sops-secrets "no runtime secrets deployed on this host"
fi
