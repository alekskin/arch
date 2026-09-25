#!/bin/bash
# Wi-Fi regulatory country. Run as root (bootstrap.sh / setup.sh via sudo).
#
# Without this the kernel stays in the "world" domain (00): 2.4 GHz channels
# 12-13 are off and 5 GHz DFS channels (52-144) are passive-only, and the
# brcmfmac firmware (no CLM blob for the BCM43602) keeps its own restrictive
# default. Home routers pick their channel automatically, so a network that
# worked yesterday can silently vanish from scans when the router moves to one
# of those channels — "sometimes it connects, sometimes it doesn't".
#
# Country: $WIFI_COUNTRY if set, otherwise derived from the timezone.

set -euo pipefail

country=${WIFI_COUNTRY:-}
if [[ -z "$country" ]]; then
  tz=$(readlink -f /etc/localtime 2>/dev/null || true)
  tz=${tz#*/zoneinfo/}
  if [[ -n "$tz" ]]; then
    country=$(awk -v tz="$tz" '$3 == tz { print substr($1, 1, 2); exit }' \
      /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab 2>/dev/null || true)
  fi
fi
country=${country^^}

if [[ ! "$country" =~ ^[A-Z]{2}$ ]]; then
  echo "wifi-regdom: no country (set WIFI_COUNTRY=XX or the timezone); leaving world domain" >&2
  exit 0
fi

# Applied when cfg80211 loads, before any driver scans.
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/cfg80211-regdom.conf <<EOF
# Written by wifi-regdom.sh — see ~/arch/config/wifi-regdom.sh
options cfg80211 ieee80211_regdom=$country
EOF

# wireless-regdb's own udev hook reads this one.
cat > /etc/conf.d/wireless-regdom <<EOF
# Written by wifi-regdom.sh — see ~/arch/config/wifi-regdom.sh
WIRELESS_REGDOM="$country"
EOF

# Apply now on a booted system (no-op in a chroot, where the host owns the kernel).
# If cfg80211 loaded before wireless-regdb was installed, it cached "no
# regulatory.db" and `iw reg set` silently does nothing — reload it first.
if command -v iw >/dev/null && [[ -d /sys/module/cfg80211 ]] && ! systemd-detect-virt -qr 2>/dev/null; then
  iw reg reload || true
  iw reg set "$country" || true
fi
echo "wifi-regdom: $country"
