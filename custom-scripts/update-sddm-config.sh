#!/usr/bin/env bash

# Define the content of the sddm configuration file
sddm_config_content="[Autologin]
Relogin=false
Session=
User=

[General]
DisplayServer=x11
GreeterEnvironment=
HaltCommand=/usr/bin/systemctl poweroff
InputMethod=
Namespaces=
Numlock=none
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=catppuccin-mocha
CursorSize=32
CursorTheme=catppuccin-mocha-mauve-cursors
DisableAvatarsThreshold=7
EnableAvatars=true
FacesDir=/usr/share/sddm/faces
Font=Fira Code, 16
ThemeDir=/usr/share/sddm/themes

[Users]
DefaultPath=/usr/local/sbin:/usr/local/bin:/usr/bin
HideShells=
HideUsers=
MaximumUid=60513
MinimumUid=1000
RememberLastSession=true
RememberLastUser=true
ReuseSession=true

[Wayland]
CompositorCommand=weston --shell=kiosk
EnableHiDPI=true
SessionCommand=/usr/share/sddm/scripts/wayland-session
SessionDir=/usr/local/share/wayland-sessions,/usr/share/wayland-sessions
SessionLogFile=.local/share/sddm/wayland-session.log

[X11]
DisplayCommand=/usr/share/sddm/scripts/Xsetup
DisplayStopCommand=/usr/share/sddm/scripts/Xstop
EnableHiDPI=true
ServerArguments=-nolisten tcp
ServerPath=/usr/bin/X
SessionCommand=/usr/share/sddm/scripts/Xsession
SessionDir=/usr/local/share/xsessions,/usr/share/xsessions
SessionLogFile=.local/share/sddm/xorg-session.log
XephyrPath=/usr/bin/Xephyr"

# Check if the sddm configuration file already exists
if [ ! -f /etc/sddm.conf ]; then
  # If it doesn't exist, create the file and write the configuration content
  echo "$sddm_config_content" | sudo tee /etc/sddm.conf >/dev/null
  echo "SDDM configuration file @ /etc/sddm.conf created successfully."
else
  echo "$sddm_config_content" | sudo tee /etc/sddm.conf >/dev/null
  echo "SDDM configuration file @ /etc/sddm.conf overwritten successfully."
fi

# Define the new Inherits value
new_inherits_value="catppuccin-mocha-mauve-cursors"

# Check if the index.theme file exists
if [ -f /usr/share/icons/default/index.theme ]; then
  # If it exists, replace the Inherits value
  sudo sed -i "s/Inherits=.*/Inherits=$new_inherits_value/g" /usr/share/icons/default/index.theme
  echo "Inherits value in index.theme file updated successfully."
else
  echo "Error: index.theme file not found."
fi
