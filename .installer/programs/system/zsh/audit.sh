# shellcheck shell=bash
# Feature Audit probe for zsh (ADR 0152; contract: PROGRAM_SPEC.md). Runs per
# account (users + root — zsh owns root's shell, ADR 0146).
feature_audit_require_package zsh zsh || return 0
export TERM=xterm-256color

sh="$(getent passwd "$FA_USER" | awk -F: '{ print $7 }')"
case "$sh" in
  */zsh) feature_audit_pass zsh-login-shell "$sh" ;;
  *)     feature_audit_fail zsh-login-shell "login shell is '$sh', not zsh" ;;
esac

# _probe_zsh_interactive <cmd> — run <cmd> in an interactive zsh on a real pty
# (zle and p10k need a terminal, as in kitty); prints its output.
_probe_zsh_interactive() {
  script -qec "zsh -i -c '$1'" /dev/null 2>&1 | awk '{ gsub(/\r/, ""); print }'
}

_probe_zsh_startup() {
  ! _probe_zsh_interactive exit \
    | grep -iE "error|not found|can.t|warning|no such"
}
feature_audit_check zsh-startup \
  "interactive zsh starts with no errors" _probe_zsh_startup

# zinit plugins load from the pre-warmed cache (offline-safe) and are live.
_probe_zsh_function() { zsh -i -c "(( \$+functions[$1] ))" 2>/dev/null; }
feature_audit_check zsh-autosuggestions "zsh-autosuggestions loaded" \
  _probe_zsh_function _zsh_autosuggest_start
feature_audit_check zsh-syntax-highlighting "zsh-syntax-highlighting loaded" \
  _probe_zsh_function _zsh_highlight
feature_audit_check zsh-p10k \
  "powerlevel10k prompt loaded" _probe_zsh_function p10k
feature_audit_check zsh-completions "compinit ran (completion system live)" \
  _probe_zsh_function compdef

feature_audit_check zsh-theme "Noctalia palette theme seeded" \
  test -f "$FA_HOME/.zsh/themes/noctalia.zsh"
feature_audit_check zsh-command-not-found "pkgfile database built" \
  pkgfile --list pacman
feature_audit_as_root \
  && feature_audit_check zsh-pkgfile-timer "pkgfile-update.timer enabled" \
  systemctl is-enabled --quiet pkgfile-update.timer

# keymap + every planned bind (audit-binds.jsonc / explicit bindkey lines)
_probe_zsh_emacs() { _probe_zsh_interactive 'bindkey -lL main' \
  | grep -q emacs; }
feature_audit_check zsh-emacs-keymap \
  "emacs keymap selected (bindkey -e)" _probe_zsh_emacs
_probe_zsh_bound() { _probe_zsh_interactive "bindkey -M $1 \"$2\"" \
  | grep -qw "$3"; }
if [[ -s "$FA_DIR/binds-plan.jsonl" ]]; then
  while IFS=$'\t' read -r seq map widget; do
    feature_audit_check "bind-zsh-$seq" "$seq → $widget in $map" \
      _probe_zsh_bound "$map" "$seq" "$widget"
  done < <(jq -r '[.chord, (.action | split(" ") | .[0], .[1])] | @tsv' \
             "$FA_DIR/binds-plan.jsonl")
fi
