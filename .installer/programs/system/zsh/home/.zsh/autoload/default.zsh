# Completion system. compinit is only AUTOLOADED here; the actual `compinit`
# call lives in ~/.zshrc AFTER zinit loads the completion plugins
# (zsh-completions), so their functions are on fpath before the dump is built.
# (promptinit dropped: p10k is a zinit theme, not a promptinit prompt.)
autoload -Uz compinit
zstyle :compinstall filename "$HOME/.zshrc"
