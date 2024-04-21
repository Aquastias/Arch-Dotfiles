#!/usr/bin/env bash

gnome_agent=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
kde_agent=/usr/lib/polkit-kde-authentication-agent-1

command -v $gnome_agent &>/dev/null && sleep 5 && $gnome_agent
command -v $kde_agent &>/dev/null && sleep 5 && $kde_agent