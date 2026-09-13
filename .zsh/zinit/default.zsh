# ===============================
# Zinit Setup
# ===============================

# Install zinit if not present
if [[ ! -f ~/.zinit/bin/zinit.zsh ]]; then
  mkdir -p ~/.zinit && \
    git clone https://github.com/zdharma-continuum/zinit ~/.zinit/bin
fi
source ~/.zinit/bin/zinit.zsh

# Oh My Zsh plugins
zinit light-mode for \
  OMZ::plugins/aliases \
  OMZ::plugins/archlinux \
  OMZ::plugins/colored-man-pages \
  OMZ::plugins/command-not-found \
  OMZ::plugins/cp \
  OMZ::plugins/dotenv \
  OMZ::plugins/extract \
  OMZ::plugins/eza \
  OMZ::plugins/firewalld \
  OMZ::plugins/fzf \
  OMZ::plugins/git-extras \
  OMZ::plugins/git \
  OMZ::plugins/gpg-agent \
  OMZ::plugins/history \
  OMZ::plugins/nvm \
  OMZ::plugins/ssh-agent \
  OMZ::plugins/sudo \
  OMZ::plugins/systemd \
  OMZ::plugins/urltools \
  OMZ::plugins/zsh-interactive-cd

# Zsh plugin extras
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-syntax-highlighting
