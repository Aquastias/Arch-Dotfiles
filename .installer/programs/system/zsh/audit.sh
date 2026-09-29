# shellcheck shell=bash
# Feature Audit probe for zsh (ADR 0152; contract: PROGRAM_SPEC.md). Runs per
# account (users + root — zsh owns root's shell, ADR 0146).
fa_require_pkg zsh zsh || return 0
export TERM=xterm-256color

sh="$(getent passwd "$FA_USER" | cut -d: -f7)"
case "$sh" in
  */zsh) fa_pass zsh-login-shell "$sh" ;;
  *)     fa_fail zsh-login-shell "login shell is '$sh', not zsh" ;;
esac

# _fa_zi <cmd> — run <cmd> in an interactive zsh on a real pty (zle and p10k
# need a terminal, as in kitty); prints its output.
_fa_zi() { script -qec "zsh -i -c '$1'" /dev/null 2>&1 | tr -d '\r'; }

_fa_zsh_startup() {
  ! _fa_zi exit | grep -iE "error|not found|can.t|warning|no such"
}
fa_check zsh-startup "interactive zsh starts with no errors" _fa_zsh_startup

# zinit plugins load from the pre-warmed cache (offline-safe) and are live.
_fa_zsh_fn() { zsh -i -c "(( \$+functions[$1] ))" 2>/dev/null; }
fa_check zsh-autosuggestions "zsh-autosuggestions loaded" \
  _fa_zsh_fn _zsh_autosuggest_start
fa_check zsh-syntax-highlighting "zsh-syntax-highlighting loaded" \
  _fa_zsh_fn _zsh_highlight
fa_check zsh-p10k "powerlevel10k prompt loaded" _fa_zsh_fn p10k
fa_check zsh-completions "compinit ran (completion system live)" \
  _fa_zsh_fn compdef

fa_check zsh-theme "Noctalia palette theme seeded" \
  test -f "$FA_HOME/.zsh/themes/noctalia.zsh"
fa_check zsh-command-not-found "pkgfile database built" \
  pkgfile --list pacman
fa_as_root && fa_check zsh-pkgfile-timer "pkgfile-update.timer enabled" \
  systemctl is-enabled --quiet pkgfile-update.timer

# keymap + every planned bind (audit-binds.jsonc / explicit bindkey lines)
_fa_zsh_emacs() { _fa_zi 'bindkey -lL main' | grep -q emacs; }
fa_check zsh-emacs-keymap "emacs keymap selected (bindkey -e)" _fa_zsh_emacs
_fa_zsh_bound() { _fa_zi "bindkey -M $1 \"$2\"" | grep -qw "$3"; }
if [[ -s "$FA_DIR/binds-plan.jsonl" ]]; then
  while IFS=$'\t' read -r seq map widget; do
    fa_check "bind-zsh-$seq" "$seq → $widget in $map" \
      _fa_zsh_bound "$map" "$seq" "$widget"
  done < <(jq -r '[.chord, (.action | split(" ") | .[0], .[1])] | @tsv' \
             "$FA_DIR/binds-plan.jsonl")
fi
