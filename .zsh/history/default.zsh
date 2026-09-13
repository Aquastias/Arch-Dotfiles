# History settings. hist_ignore_space: drop space-prefixed commands;
# hist_reduce_blanks: collapse redundant whitespace before saving.
setopt histignorealldups sharehistory hist_ignore_space hist_reduce_blanks

HISTFILE=~/.histfile
HISTSIZE=50000
SAVEHIST=50000
# Scalar glob pattern (NOT an array) — keeps piped-password sudo lines out.
HISTORY_IGNORE='(*sudo -S*)'
