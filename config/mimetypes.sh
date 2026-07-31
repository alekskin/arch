#!/bin/bash
# Default application associations (user-level xdg-mime).
# Run as the real desktop user, not root.

set -euo pipefail

# PDF → Evince (same as Omarchy Document Viewer)
if [[ -f /usr/share/applications/org.gnome.Evince.desktop ]]; then
  xdg-mime default org.gnome.Evince.desktop application/pdf
fi

# Images → imv (same as Omarchy)
if [[ -f /usr/share/applications/imv.desktop ]]; then
  for mime in image/png image/jpeg image/gif image/webp image/bmp image/tiff; do
    xdg-mime default imv.desktop "$mime"
  done
fi

# Videos → mpv
if [[ -f /usr/share/applications/mpv.desktop ]]; then
  for mime in \
    video/mp4 video/x-msvideo video/x-matroska video/x-flv video/x-ms-wmv \
    video/mpeg video/ogg video/webm video/quicktime video/3gpp video/3gpp2 \
    video/x-ms-asf video/x-ogm+ogg video/x-theora+ogg application/ogg
  do
    xdg-mime default mpv.desktop "$mime"
  done
fi

# Directories → Thunar
if [[ -f /usr/share/applications/thunar.desktop ]]; then
  xdg-mime default thunar.desktop inode/directory
fi

# Browser if Chromium present
if [[ -f /usr/share/applications/chromium.desktop ]]; then
  xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true
  xdg-mime default chromium.desktop x-scheme-handler/http
  xdg-mime default chromium.desktop x-scheme-handler/https
fi
