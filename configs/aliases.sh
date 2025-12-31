#!/usr/bin/env bash
# rice aliases - managed by rice
# shellcheck shell=bash
# https://github.com/pentaxis93/rice

# Modern replacements
command -v lsd &>/dev/null && alias ls='lsd'
command -v bat &>/dev/null && alias cat='bat --paging=never'
command -v rg &>/dev/null && alias grep='rg'
command -v hx &>/dev/null && alias vim='hx'
command -v lazygit &>/dev/null && alias lg='lazygit'
command -v trash-put &>/dev/null && alias rm='trash-put'

# ls aliases (work with lsd or regular ls)
alias ll='ls -lh'
alias la='ls -lah'
alias lt='ls --tree'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Git shortcuts (supplement oh-my-zsh git plugin)
alias gs='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gp='git push'
alias gl='git pull'
alias glog='git log --oneline --graph --decorate -20'

# Safety
alias cp='cp -i'
alias mv='mv -i'

# Convenience
alias c='clear'
alias e='$EDITOR'
alias ports='lsof -i -P -n | grep LISTEN'
alias myip='curl -s https://ipinfo.io/ip'
alias weather='curl -s "wttr.in?format=3"'

# Disk usage
alias df='df -h'
alias du='du -h'
alias duf='du -sh * | sort -h'

# Process management
alias psg='ps aux | grep -v grep | grep'

# Tar shortcuts
alias untar='tar -xvf'
alias mktar='tar -cvf'
alias mktgz='tar -czvf'

# Date/time
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias week='date +%V'
