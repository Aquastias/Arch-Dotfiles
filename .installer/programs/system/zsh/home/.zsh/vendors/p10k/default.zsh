# Powerlevel10k prompt (zinit-managed). The instant-prompt preamble lives at the
# top of ~/.zshrc (it must precede any console output); this only loads the
# theme and its config.
zinit light romkatv/powerlevel10k

# Committed prompt config, then the Noctalia-generated accent override (only the
# accent-carrying *_FOREGROUND keys). Override is sourced AFTER .p10k.zsh so it
# wins; seed-only, rewritten live on palette change in compositor sessions.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
[[ -f "$HOME/.zsh/themes/p10k-accent.zsh" ]] \
  && source "$HOME/.zsh/themes/p10k-accent.zsh"
