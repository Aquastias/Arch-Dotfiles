# shellcheck shell=bash
# audit-timeout: 1800
# Feature Audit probe for emacs (ADR 0152, 0160; contract: PROGRAM_SPEC.md).
# Runs in the user's real Doom: the seeded config is placed, Doom core sits
# at the pinned commit, `doom doctor` reports no errors, and every bind the
# shipped config.el maps resolves to its command — nvim's map won over
# Doom's defaults (audit-binds.jsonc; judged in one throwaway daemon).
feature_audit_require_package emacs emacs-wayland || return 0
feature_audit_as_user || return 0
# The runner's FA_DIR ends in "/": Emacs' `load' reads "dir//file" as "/file".
fixtures="$(readlink -m "$FA_DIR")/audit-fixtures"  # readlink -m: no trailing /
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
    || { printf '%s\n' "$out" | tail -n 1; return 1; }
  local failed='There (is|are) [0-9]+ errors?!|Attempt to load DOOM failed'
  if printf '%s\n' "$out" | grep -qE "$failed"; then
    # The first error line.
    printf '%s\n' "$out" | grep -E 'errors?!|failed' | head -n 1
    return 1
  fi
}
feature_audit_check emacs-doom-doctor "doom doctor reports no errors" \
  _probe_emacs_doctor

if [[ ! -f "$FA_DIR/binds-plan.jsonl" ]]; then
  feature_audit_skip emacs-binds "no plan staged"; return 0
fi
plan="$(mktemp)" out="$(mktemp)" log="$(mktemp)" socket="fa-emacs-probe-$$"
# Each bind's chord, states (its action's first word), effect and argument,
# joined by the unit separator (\x1f), which no field contains.
# shellcheck disable=SC2016 # a jq program, not shell
bind_fields='[.chord, (.action | split(" ")[0]), (.effect // "none"),
  (.arg // "")] | join("\u001f")'
# A bind with no expectation is a Finding; the rest go to the judge as
# states, chord, wanted command, check id (ids carry the states: gsa is
# bound in normal and visual).
while IFS=$'\x1f' read -r chord states effect arg; do
  id="bind-emacs-$states-$(printf '%s' "$chord" | tr ' ' '_')"
  if [[ "$effect" == none ]]; then
    feature_audit_fail emacs-untested-bind "$states $chord has no expectation"
    continue
  fi
  printf '%s\t%s\t%s\t%s\n' "$states" "$chord" "$arg" "$id" >> "$plan"
done < <(jq -r "$bind_fields" "$FA_DIR/binds-plan.jsonl")

if timeout 600 emacs --daemon="$socket" >"$log" 2>&1; then
  timeout 300 emacsclient -s "$socket" -e "(progn
    (load \"$fixtures/binds.el\" nil t)
    (fa-emacs-binds \"$plan\" \"$out\"))" >/dev/null 2>"$log"
  if [[ -s "$out" ]]; then cat "$out"
  else
    feature_audit_fail emacs-binds \
      "bind judge returned nothing: $(head -n 1 "$log")"
  fi
  emacsclient -s "$socket" -e '(kill-emacs)' >/dev/null 2>&1
else
  feature_audit_fail emacs-daemon \
    "Doom did not start: $(head -n 1 "$log")"
fi
rm -f "$plan" "$out" "$log"
