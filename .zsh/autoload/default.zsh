# Prompt
autoload -Uz promptinit && promptinit

# Completion system
autoload -Uz compinit && compinit -C
zstyle :compinstall filename "$HOME/.zshrc"
