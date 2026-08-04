#!/bin/bash
# Stage 1 — run as ROOT, right after installing Arch.
#
# A fresh install has no networking (the live ISO's connection is not carried
# over), and setup.sh needs the network from its very first step. This brings
# the machine online and installs the bare minimum to fetch the rest.
#
# Then log in as your normal user and run ./setup.sh (stage 2), which installs
# the packages and desktop — that part must not run as root, because makepkg
# refuses to and dotfiles belong in a real $HOME.
#
# Usage (as root):
#   ./bootstrap.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $EUID -ne 0 ]]; then
  echo "bootstrap.sh must run as root (it configures networking)." >&2
  echo "Already online with a user? You want ./setup.sh instead." >&2
  exit 1
fi

echo "=== Arch bootstrap (stage 1: network) ==="

# ---------------------------------------------------------------------------
# A normal user must already exist — archinstall creates one, and stage 2 runs
# as that user. Creating users is not this script's job.
# ---------------------------------------------------------------------------
existing_user=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
if [[ -z "$existing_user" ]]; then
  echo "" >&2
  echo "No normal user account found — only root." >&2
  echo "Create one (archinstall: 'User account' → add a superuser), then re-run." >&2
  echo "" >&2
  exit 1
fi
echo "user: found $existing_user"

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
have_network() {
  # resolved may not be up yet, so try a bare IP as well as a name.
  ping -c1 -W2 9.9.9.9 &>/dev/null || ping -c1 -W2 archlinux.org &>/dev/null
}

echo "network: started"

# Wired DHCP via systemd-networkd — part of systemd, nothing to download.
mkdir -p /etc/systemd/network
cp "$SCRIPT_DIR/systemd/20-wired.network" /etc/systemd/network/20-wired.network
systemctl enable --now systemd-networkd systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Give DHCP a moment to get a lease.
for _ in {1..10}; do
  have_network && break
  sleep 1
done

# No wired link: fall back to Wi-Fi, which needs iwd to already be installed
# (it can't be downloaded without a network).
if ! have_network; then
  echo "network: no wired connection"
  if command -v iwctl >/dev/null; then
    mkdir -p /etc/iwd
    cp "$SCRIPT_DIR/iwd/main.conf" /etc/iwd/main.conf
    systemctl enable --now iwd
    sleep 1
    dev=$(iwctl device list 2>/dev/null | awk '/wlan|wlp/ { print $2; exit }')
    dev=${dev:-wlan0}
    echo ""
    echo "Connect Wi-Fi from another TTY (Alt+F2), or here:"
    echo "  iwctl station $dev get-networks"
    echo "  iwctl station $dev connect <SSID>"
    echo ""
    while ! have_network; do
      read -r -p "Press Enter to re-test the connection (Ctrl+C to abort): " _ || exit 1
    done
  else
    echo "network: iwd is not installed, so Wi-Fi cannot be configured offline." >&2
    echo "Plug in Ethernet, or reinstall choosing a network option in archinstall." >&2
    exit 1
  fi
fi
echo "network: finished (online)"

# ---------------------------------------------------------------------------
# Minimum needed to fetch and run stage 2
# ---------------------------------------------------------------------------
echo "packages: sudo + git"
pacman -Sy --needed --noconfirm sudo git

# ---------------------------------------------------------------------------
echo ""
echo "=== Stage 1 done — this machine is online ==="
echo "Now log in as your user and run stage 2:"
echo ""
echo "  su - $existing_user"
echo "  git clone https://github.com/alekskin/arch.git ~/arch"
echo "  cd ~/arch && ./setup.sh"
echo ""
