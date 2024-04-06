#!/usr/bin/env bash

# shellcheck source=/dev/null

export SSH_ASKPASS=/usr/lib/ssh/ssh-askpass

SSH_ENV="$HOME/.ssh/environment"
SSH_GMAIL_ACCOUNT="alexandrumlakar@gmail.com"
SSH_PROTONMAIL_ACCOUNT="alexandrumlakar@protonmail.com"


# Generate an SSH key pair
function ssh_gen_gmail() {
  ssh-keygen -t rsa -b 4096 -C "$SSH_GMAIL_ACCOUNT"
}

function ssh_gen_pmail() {
  ssh-keygen -t rsa -b 4096 -C "$SSH_PROTONMAIL_ACCOUNT"
}

# List all available SSH keys
function ssh_list() {
  ls -la ~/.ssh/*.pub
}

# Add SSH key to the ssh-agent, so that you don't have to
# enter the passphrase every time you use the SSH key
function ssh_add() {
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/id_rsa
}

# Start the ssh-agent in the background
function ssh_agent_start {
  echo "Initializing new SSH agent..."
  /usr/bin/ssh-agent | sed 's/^echo/#echo/' >"${SSH_ENV}"
  echo succeeded
  chmod 600 "${SSH_ENV}"
  . "${SSH_ENV}" >/dev/null
  /usr/bin/ssh-add
}

# Source SSH settings, if applicable.
if [ -f "${SSH_ENV}" ]; then
  . "${SSH_ENV}" >/dev/null
  #ps ${SSH_AGENT_PID} doesn't work under cywgin
  pgrep -f "ssh-agent -s$" >/dev/null || {
    ssh_agent_start
  }
else
  ssh_agent_start
fi
