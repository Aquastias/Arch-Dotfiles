# shellcheck shell=bash
# audit-timeout: 1800
# Feature Audit probe for emacs (ADR 0152, 0160; contract: PROGRAM_SPEC.md).
# Runs in the user's real Doom: the seeded config is placed, Doom core sits
# at the pinned commit, `doom doctor` reports no errors, and every bind the
# shipped config.el maps resolves to its command — nvim's map won over
# Doom's defaults (audit-binds.jsonc; judged in one throwaway daemon).
feature_audit_require_package emacs emacs-wayland || return 0
feature_audit_as_user || return 0
fixtures="$FA_DIR/audit-fixtures"
doom_core="$FA_HOME/.config/emacs"

feature_audit_check emacs-runs "emacs --version" emacs --version
feature_audit_check emacs-config "seeded Doom config present" \
  test -s "$FA_HOME/.config/doom/init.el"

_probe_emacs_pin() {
  local want have
  want="$(grep -vE '^[[:space:]]*(#|$)' "$fixtures/doom-ref")"
  have="$(git -C "$doom_core" rev-parse HEAD 2>/dev/null)"
  [[ "$have" == "$want" ]] \
    || { echo "at ${have:-no clone}, not $want"; return 1; }
}
feature_audit_check emacs-doom-pinned "Doom core at the pinned commit" \
  _probe_emacs_pin

# doom doctor exits 0 either way: judge its summary (warnings pass).
_probe_emacs_doctor() {
  local out
  out="$("$doom_core/bin/doom" doctor 2>&1)" \
    || { awk 'END { print }' <<<"$out"; return 1; }
  if grep -qE 'There (is|are) [0-9]+ errors?!|Attempt to load DOOM failed' \
    <<<"$out"; then
    grep -m1 -E 'errors?!|failed' <<<"$out"
    return 1
  fi
}
feature_audit_check emacs-doom-doctor "doom doctor reports no errors" \
  _probe_emacs_doctor

if [[ ! -f "$FA_DIR/binds-plan.jsonl" ]]; then
  feature_audit_skip emacs-binds "no plan staged"; return 0
fi
plan="$(mktemp)" out="$(mktemp)" log="$(mktemp)" socket="fa-emacs-probe-$$"
# A bind with no expectation is a Finding; the rest go to the judge as
# states, chord, wanted command, check id (ids carry the states: gsa is
# bound in normal and visual).
while IFS=$'\x1f' read -r chord states effect arg; do
  id="bind-emacs-$states-${chord// /_}"
  if [[ "$effect" == none ]]; then
    feature_audit_fail emacs-untested-bind "$states $chord has no expectation"
    continue
  fi
  printf '%s\t%s\t%s\t%s\n' "$states" "$chord" "$arg" "$id" >> "$plan"
done < <(jq -r '[.chord, (.action | split(" ")[0]), (.effect // "none"),
                 (.arg // "")] | join("\u001f")' "$FA_DIR/binds-plan.jsonl")

if timeout 600 emacs --daemon="$socket" >"$log" 2>&1; then
  timeout 300 emacsclient -s "$socket" -e "(progn
    (load \"$fixtures/binds.el\" nil t)
    (fa-emacs-binds \"$plan\" \"$out\"))" >/dev/null 2>&1
  cat "$out"
  emacsclient -s "$socket" -e '(kill-emacs)' >/dev/null 2>&1
else
  feature_audit_fail emacs-daemon \
    "Doom did not start: $(awk 'NR == 1 { print; exit }' "$log")"
fi
rm -f "$plan" "$out" "$log"
