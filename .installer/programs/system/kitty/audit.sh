# shellcheck shell=bash
# Feature Audit probe for kitty (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package kitty kitty || return 0
feature_audit_as_user || return 0

feature_audit_check kitty-config "curated kitty.conf applied" \
  test -f "$FA_HOME/.config/kitty/kitty.conf"
feature_audit_check kitty-theme "Noctalia theme include present" \
  test -f "$FA_HOME/.config/kitty/themes/noctalia.conf"

if [[ "$FA_SESSION" == none || -z "${WAYLAND_DISPLAY:-}" ]]; then
  feature_audit_skip kitty-launch "no live session"
  return 0
fi
# A real window: config errors surface on stderr at startup. With no Wayland
# shell there is no notification daemon, so kitty's startup query of its
# capabilities fails: tolerate exactly that line there.
_kitty=(timeout 20 kitty --class fa-probe-kitty -e sh -c 'sleep 3')
_judge=(feature_audit_no_stderr)
feature_audit_has_shell || _judge=(feature_audit_no_stderr_but '\[glfw error [0-9]+\]: Notify: ')
feature_audit_check kitty-launch "kitty opens a window with no config errors" \
  "${_judge[@]}" "${_kitty[@]}"
