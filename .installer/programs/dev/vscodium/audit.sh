# shellcheck shell=bash
# Feature Audit probe for vscodium (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg vscodium vscodium-bin || fa_require_pkg vscodium vscodium \
  || return 0
fa_as_user || return 0
fa_check codium-runs "codium --version" codium --version
fa_check codium-settings "seeded settings.json present" \
  test -s "$FA_HOME/.config/VSCodium/User/settings.json"
# every declared extension is installed (offline: no marketplace fetch)
_fa_codium_ext() {
  local have want missing=""
  have="$(codium --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  while read -r want; do
    grep -qx "${want,,}" <<<"$have" || missing+=" $want"
  done < <(grep -vE '^\s*(#|$)' "$FA_DIR/audit-fixtures/extensions.txt")
  [[ -z "$missing" ]] || { echo "missing:$missing"; return 1; }
}
fa_check codium-extensions "declared extensions installed" _fa_codium_ext
