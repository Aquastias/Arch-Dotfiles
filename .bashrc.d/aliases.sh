#!/usr/bin/env bash

# shellcheck source=/dev/null

# Alias definitions.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

# Variables
SUDO="sudo"
BASHRC_SOURCE="$HOME/.bashrc"

### Reload/edit bashrc
alias reloadbashrc='source $BASHRC_SOURCE';
alias editbashrc='nano $BASHRC_SOURCE';
###

### System upgrade
alias system-upgrade='paru -Syyu'
###

### Set the default editor
export EDITOR=nano
export VISUAL=nano
###

### Modified commands
alias grep='grep --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -iv'
alias mkdir='mkdir -p'
alias ps='ps auxf'
alias ping='ping -c 10'
alias less='less -R'
alias cls='clear'
alias freshclam='sudo freshclam'
alias vi='nvim'
alias vim='nvim'
alias svi='sudo vi'
alias vis='nvim "+set si"'
###

### Change directory aliases
alias web='cd /var/www/html'
alias home='cd ~'
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
###

### Directory utils
alias cpp='copy_progress_bar'
alias cpg='copy_and_go'
alias mvg='move_and_go'
alias mkdirg='mkdir_and_go'
alias updir='up_n_dirs'
alias pwdt='pwd_last_two'
###

### Remove a directory and all files
alias rmd='/bin/rm  --recursive --force --verbose '
###

### Multiple directory listing commands
alias ls='ls --color=auto' # add colors
alias la='ls -Alh' # show hidden files
alias ls='ls -aFh --color=always' # add colors and file type extensions
alias lx='ls -lXBh' # sort by extension
alias lk='ls -lSrh' # sort by size
alias lc='ls -lcrh' # sort by change time
alias lu='ls -lurh' # sort by access time
alias lr='ls -lRh' # recursive ls
alias lt='ls -ltrh' # sort by date
alias lm='ls -alh |more' # pipe through 'more'
alias lw='ls -xAh' # wide listing format
alias ll='ls -Fls' # long listing format
alias labc='ls -lap' #alphabetical sort
alias lf="ls -l | egrep -v '^d'" # files only
alias ldir="ls -l | egrep '^d'" # directories only
###

### Multiple directory listing commands passed through exa
alias exa='exa -aFh --color=always' # add colors and file type extensions
alias exal='exa -Alh' # show hidden files
alias exax='exa -lXBh' # sort by extension
alias exak='exa -lSrh' # sort by size
alias exac='exa -lcrh' # sort by change time
alias exau='exa -lurh' # sort by access time
alias exar='exa -lRh' # recursive ls
alias exat='exa -ltrh' # sort by date
alias exam='exa -alh |more' # pipe through 'more'
alias exaw='exa -xAh' # wide listing format
alias exall='exa -Fls' # long listing format
alias exalabc='exa -lap' #alphabetical sort
alias exalf="exa -l | egrep -v '^d'" # files only
alias exaldir="exa -l | egrep '^d'" # directories only
alias els='exa -l --sort=size --reverse --group-directories-first' # sort by size
alias elsa='exa -l --sort=size --reverse --group-directories-first -a' # sort by size, show hidden
alias elr='exa -l --sort=modified --reverse --group-directories-first' # sort by date
alias elra='exa -l --sort=modified --reverse --group-directories-first -a' # sort by date, show hidden
alias elc='exa -l --sort=changed --reverse --group-directories-first' # sort by date
alias elca='exa -l --sort=changed --reverse --group-directories-first -a' # sort by date, show hidden
alias ela='exa -l --sort=accessed --reverse --group-directories-first' # sort by date
alias elaa='exa -l --sort=accessed --reverse --group-directories-first -a' # sort by date, show hidden
alias elx='exa -l --sort=extension --reverse --group-directories-first' # sort by extension
alias elxa='exa -l --sort=extension --reverse --group-directories-first -a' # sort by extension, show hidden
alias eln='exa -l --sort=name --reverse --group-directories-first' # sort by name
alias elna='exa -l --sort=name --reverse --group-directories-first -a' # sort by name, show hidden
alias eli='exa -l --sort=inode --reverse --group-directories-first' # sort by inode
alias elia='exa -l --sort=inode --reverse --group-directories-first -a' # sort by inode, show hidden
alias elu='exa -l --sort=none --reverse --group-directories-first' # sort by none
alias elua='exa -l --sort=none --reverse --group-directories-first -a' # sort by none, show hidden
alias el='exa -l --sort=extension --reverse --group-directories-first' # sort by extension
alias ela='exa -l --sort=extension --reverse --group-directories-first -a' # sort by extension, show hidden
alias eln='exa -l --sort=name --reverse --group-directories-first' # sort by name
alias elna='exa -l --sort=name --reverse --group-directories-first -a' # sort by name, show hidden
###

### Chmod commands
alias mx='chmod a+x'
alias 000='chmod -R 000'
alias 400='chmod -R 400'
alias 444='chmod -R 444'
alias 600='chmod -R 600'
alias 644='chmod -R 644'
alias 666='chmod -R 666'
alias 700='chmod -R 700'
alias 755='chmod -R 755'
alias 777='chmod -R 777'
###

### History commands
alias h='history'
alias hg='history | grep'
alias hgrep='history | grep'
###

### Search running processes
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'
alias psgrep='ps aux | grep -v grep | grep -i -e VSZ -e'
alias topcpu='ps auxf | sort -nr -k 3 | head -10'
###

### Search files in current folder
alias f='find . | grep -i -e';
alias fgrep='find . | grep -i -e';
alias ftext='find_text_in_files'
###

### Count all files (recursively) in the current folder
alias countfiles='find . -type f | wc -l'
###

### To see if a command is aliased, a file, or a built-in command
alias checkcommand="type -t"
###

### Network commands
alias netinfo='network_info'
alias whatismyip="whatsmyip"
alias connections='ss | less' # get all connections
alias connectionstcpnlm='ss -t' # get TCP connections not in listen mode
alias connectionsudpsnlm='ss -u' # get UDP connections not in listen mode
alias connectionsunix='ss -x' # get Unix domain socket connections
alias connectionstcpa='ss -at' # get all TCP connections (both listening and non-listening)
alias connectionsudpa='ss -au' # get all UDP connections
alias connectionsnsnr='ss -tn' # TCP without service name resolution
alias connectionsnsnrl='ss -ltn' # listening TCP without service name resolution
alias connectionstcppn='ss -ltp' # listening TCP with PID and name
alias connectionsstat='ss -s' # prints statistics
alias connectionstcptimer='ss -tn -o' # TCP connections, show keepalive timer
alias connectionsipv4='ss -lt4' # IPv4 (TCP) connections
alias openports='ss -lntu' # open ports
alias ipview='ip addr show' # view IP addresses
###

### Disk space and space used in a folder
alias diskspace="du -S | sort -n -r |more"
alias folders='du -h --max-depth=1'
alias folderssort='find . -maxdepth 1 -type d -print0 | xargs -0 du -sk | sort -rn'
alias tree='tree -CAhF --dirsfirst'
alias treed='tree -CAFd'
alias mountedinfo='df -hT'
###

### Archives commands
alias extractarchive='extract_archive'
alias untar='tar -zxvf'
alias untarbz2='tar -jxvf'
alias untargz='tar -zxvf'
alias untarxz='tar -Jxvf'
alias untarzip='unzip'
alias untarrar='unrar x'
alias untar7z='7z x'
alias untarxz='tar -Jxvf'
alias mkzip='zip -r'
alias mktar='tar -czvf'
alias mktarbz2='tar -cjvf'
alias mktarxz='tar -cJvf'
alias mktargz='tar -czvf'
alias mktarxz='tar -cJvf'
alias mktarrar='rar a'
alias mktar7z='7z a'
###''

### Pacman
alias pacrmdb='$SUDO rm /var/lib/pacman/db.lck'
###

### CKB Next
alias ckb-reload='$SUDO systemctl enable --now ckb-next-daemon'
###

### Cht.sh
alias chtsh='chtsh'
###

### SSH
alias sshgeng='ssh_gen_gmail'
alias sshgenp='ssh_gen_pmail'
alias sshlist='ssh_list'
alias sshadd='ssh_add'
###