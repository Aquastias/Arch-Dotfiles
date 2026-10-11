# shellcheck shell=bash
# Feature Audit probe for borg (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package borg borg || return 0
if feature_audit_as_root; then
  feature_audit_check borg-timer "borgmatic.timer enabled" \
    systemctl is-enabled --quiet borgmatic.timer
  feature_audit_check borgmatic-config "borgmatic config validates" \
    borgmatic config validate
  return 0
fi
feature_audit_check vorta-installed \
  "Vorta GUI installed" feature_audit_installed vorta
# Backup + restore round trip in a throwaway repo.
_probe_borg_roundtrip() {
  local directory; directory="$(mktemp -d)"
  export BORG_PASSPHRASE=fa BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
  mkdir -p "$directory/src" "$directory/out"; echo fa-data > \
    "$directory/src/file"
  borg init -e repokey "$directory/repo" \
    && borg create "$directory/repo::a" "$directory/src" \
    && (cd "$directory/out" && borg extract "$directory/repo::a") \
    && cmp "$directory/src/file" "$directory/out${directory}/src/file"
  local rc=$?; rm -rf "$directory"; return "$rc"
}
feature_audit_check borg-roundtrip "borg init/create/extract round trip" \
  _probe_borg_roundtrip
