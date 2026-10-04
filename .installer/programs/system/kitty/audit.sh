# shellcheck shell=bash
# Feature Audit probe for kitty (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg kitty kitty || return 0
fa_as_user || return 0

fa_check kitty-config "curated kitty.conf applied" \
  test -f "$FA_HOME/.config/kitty/kitty.conf"
fa_check kitty-theme "Noctalia theme include present" \
  test -f "$FA_HOME/.config/kitty/themes/noctalia.conf"

if [[ "$FA_SESSION" == none || -z "${WAYLAND_DISPLAY:-}" ]]; then
  fa_skip kitty-launch "no live session"
  return 0
fi
# A real window: config errors surface on stderr at startup. With no Wayland
# shell there is no notification daemon, so kitty's startup query of its
# capabilities fails: tolerate exactly that line there.
_kitty=(timeout 20 kitty --class fa-probe-kitty -e sh -c 'sleep 3')
_judge=(fa_no_stderr)
fa_has_shell || _judge=(fa_no_stderr_but '\[glfw error [0-9]+\]: Notify: ')
fa_check kitty-launch "kitty opens a window with no config errors" \
  "${_judge[@]}" "${_kitty[@]}"
