#!/usr/bin/env bash

PATH=/usr/bin
ALERT="Signature detected by clamav: $CLAM_VIRUSEVENT_VIRUSNAME in $CLAM_VIRUSEVENT_FILENAME"

# Send an alert to all graphical users.
for ADDRESS in /run/user/*; do
  USERID=${ADDRESS#/run/user/}
  /usr/bin/sudo -u "#$USERID" DBUS_SESSION_BUS_ADDRESS="unix:path=$ADDRESS/bus" PATH=${PATH} \
    /usr/bin/notify-send -a "ClamAV Virus Event" -h "string:desktop-entry:clamav" -t 15000 -i clamav "[WARNING] Virus found!" "$ALERT"
done
