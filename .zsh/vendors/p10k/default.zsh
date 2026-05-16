# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
_p10k_instant_prompt="${XDG_CACHE_HOME:-$HOME/.cache}"
_p10k_instant_prompt+="/p10k-instant-prompt-${(%):-%n}.zsh"
if [[ -r "$_p10k_instant_prompt" ]]; then
  source "$_p10k_instant_prompt"
fi
unset _p10k_instant_prompt

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

zinit light romkatv/powerlevel10k

