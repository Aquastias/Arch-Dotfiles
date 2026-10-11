# shellcheck shell=bash
# Feature Audit probe for vscodium (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package vscodium vscodium-bin || feature_audit_require_package vscodium vscodium \
  || return 0
feature_audit_as_user || return 0
feature_audit_check codium-runs "codium --version" codium --version
feature_audit_check codium-settings "seeded settings.json present" \
  test -s "$FA_HOME/.config/VSCodium/User/settings.json"
# every declared extension is installed (offline: no marketplace fetch)
_probe_codium_ext() {
  local have want missing=""
  have="$(codium --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  while read -r want; do
    grep -qx "${want,,}" <<<"$have" || missing+=" $want"
  done < <(grep -vE '^\s*(#|$)' "$FA_DIR/audit-fixtures/extensions.txt")
  [[ -z "$missing" ]] || { echo "missing:$missing"; return 1; }
}
feature_audit_check codium-extensions "declared extensions installed" _probe_codium_ext
