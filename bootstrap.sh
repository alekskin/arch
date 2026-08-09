#!/bin/bash
# Stage 1 — run as ROOT. Brings a fresh Arch install online, permanently.
#
# Run it in EITHER of two places:
#
#   A. From the live ISO, before the first reboot (recommended):
#        arch-chroot /mnt /root/arch/bootstrap.sh
#      The ISO's network (Ethernet, Wi-Fi, USB tethering) is still up, so this
#      can install the drivers and daemons the installed system will need to
#      get online by itself — which it cannot download once it is offline.
#
#   B. On the booted system, if it already has some way online.
#
# It detects which case it is in: inside a chroot there is no PID 1, so units
# are only enabled (they start on the next boot) and the network is assumed to
# come from the host.
#
# Then log in as your normal user and run ./setup.sh (stage 2), which installs
# the packages and desktop — that part must not run as root, because makepkg
# refuses to and dotfiles belong in a real $HOME.
#
# Env vars:
#   INSTALL_HARDWARE=macbook|amd|none   skip hardware auto-detection
#   SKIP_CACHE=1                        don't pre-download the stage 2 packages

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $EUID -ne 0 ]]; then
  echo "bootstrap.sh must run as root (it configures networking)." >&2
  echo "Already online with a user? You want ./setup.sh instead." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Where are we? Inside a chroot systemd is not running: `systemctl start` fails
# and there is nothing to wait for a DHCP lease from. `systemctl enable` is
# just symlinks, so that works fine.
# ---------------------------------------------------------------------------
# NB: /run/systemd/system is NOT a usable signal here — arch-chroot bind-mounts
# /run from the live ISO, so the host's systemd runtime dir is visible inside.
# Compare our root against PID 1's root instead (what systemd-detect-virt does).
IN_CHROOT=0
# `systemd-detect-virt -r` prints nothing — it answers through its exit status.
if systemd-detect-virt -r 2>/dev/null; then
  IN_CHROOT=1
elif [[ "$(stat -Lc %d:%i / 2>/dev/null)" != "$(stat -Lc %d:%i /proc/1/root/. 2>/dev/null)" ]]; then
  IN_CHROOT=1
elif ! systemctl is-system-running >/dev/null 2>&1 && ! [[ -d /run/systemd/system ]]; then
  IN_CHROOT=1
fi

if ((IN_CHROOT)); then
  echo "=== Arch bootstrap (stage 1) — chroot mode ==="
  echo "context: no init running; services will be enabled for the next boot"
else
  echo "=== Arch bootstrap (stage 1) — booted system ==="
fi

enable_unit() {
  # Enable now if we can start things, otherwise enable for the next boot.
  # --root=/ forces systemctl to write the symlinks itself instead of asking a
  # manager over D-Bus — which, with the ISO's /run bind-mounted in, would be
  # the *host's* systemd operating on the *host's* filesystem.
  if ((IN_CHROOT)); then
    systemctl --root=/ enable "$@"
  else
    systemctl enable --now "$@"
  fi
}

enable_unit_optional() {
  # Same, for units that may not exist (usbmuxd is udev-activated on Arch).
  enable_unit "$@" 2>/dev/null || true
}

read_pkg_list() {
  sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$1"
}

# ---------------------------------------------------------------------------
# A normal user must already exist — archinstall creates one, and stage 2 runs
# as that user. Creating users is not this script's job.
# ---------------------------------------------------------------------------
existing_user=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
if [[ -z "$existing_user" ]]; then
  echo "" >&2
  echo "No normal user account found — only root." >&2
  echo "Create one (archinstall: 'User account' → add a superuser), then re-run." >&2
  if ((IN_CHROOT)); then
    echo "In the chroot:  useradd -m -G wheel <name> && passwd <name>" >&2
  fi
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

# Persistent config, applied in both modes.
mkdir -p /etc/systemd/network
cp "$SCRIPT_DIR/systemd/20-wired.network" /etc/systemd/network/20-wired.network
cp "$SCRIPT_DIR/systemd/25-tether.network" /etc/systemd/network/25-tether.network
enable_unit systemd-networkd systemd-resolved

if ((IN_CHROOT)); then
  # The connection belongs to the host ISO. All we need here is working DNS so
  # pacman can download; /etc/resolv.conf inside the chroot is usually a
  # dangling stub symlink, so replace it for the duration and restore at the end.
  if ! getent hosts archlinux.org >/dev/null 2>&1; then
    echo "network: chroot has no DNS, using a temporary resolv.conf"
    rm -f /etc/resolv.conf
    printf 'nameserver 9.9.9.9\nnameserver 1.1.1.1\n' > /etc/resolv.conf
  fi
  if ! have_network && ! getent hosts archlinux.org >/dev/null 2>&1; then
    echo "" >&2
    echo "No network inside the chroot." >&2
    echo "Get the LIVE ISO online first (plug in Ethernet, iwctl, or USB" >&2
    echo "tethering), verify with 'ping archlinux.org' outside the chroot," >&2
    echo "then re-enter with 'arch-chroot /mnt' and re-run this script." >&2
    echo "" >&2
    exit 1
  fi
else
  # Booted system: bring wired/tether DHCP up and wait for a lease.
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
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
      echo "Plug in Ethernet or tether a phone over USB, or re-run this script" >&2
      echo "from the live ISO with: arch-chroot /mnt /root/arch/bootstrap.sh" >&2
      exit 1
    fi
  fi
fi
echo "network: finished (online)"

# ---------------------------------------------------------------------------
# Hardware detection — which Wi-Fi driver will this machine need after reboot?
#
# Only matters for Broadcom STA chips (MacBooks): brcmfmac does not drive them,
# and broadcom-wl cannot be downloaded once you are offline for lack of Wi-Fi.
# Inside arch-chroot /sys is bind-mounted from the host, so this sees the real
# hardware.
# ---------------------------------------------------------------------------
# PCI ids the wl driver claims. BCM43602 (43ba/43bb/43bc) and newer are handled
# by the in-kernel brcmfmac and must NOT get broadcom-wl.
WL_IDS=" 4311 4312 4313 4315 4318 4319 4320 4321 4322 4324 4325 4328 4329 432a
 432b 432c 432d 4331 4333 4335 4350 4353 4357 4358 4359 4360 4365 43a0 43a1
 43a2 43b1 4727 a8d6 "

detect_hardware() {
  local dev vendor device class
  for dev in /sys/bus/pci/devices/*; do
    [[ -r "$dev/class" ]] || continue
    class=$(<"$dev/class")
    # 0x0280xx = network controller (Wi-Fi), 0x0200xx = ethernet
    [[ "$class" == 0x0280* ]] || continue
    vendor=$(<"$dev/vendor")
    [[ "$vendor" == "0x14e4" ]] || continue
    device=$(<"$dev/device")
    device=${device#0x}
    if [[ "$WL_IDS" == *" $device "* ]]; then
      echo "macbook"
      return 0
    fi
    echo "hardware: Broadcom 14e4:$device found, but it is not a wl chip" >&2
    echo "hardware: leaving it to the in-kernel brcmfmac driver" >&2
  done
  echo "none"
}

if [[ -z "${INSTALL_HARDWARE:-}" ]]; then
  if [[ -d /sys/bus/pci/devices ]]; then
    INSTALL_HARDWARE=$(detect_hardware)
    echo "hardware: detected ${INSTALL_HARDWARE}"
  else
    INSTALL_HARDWARE=none
    echo "hardware: /sys unavailable, skipping detection (use arch-chroot, not chroot)" >&2
  fi
else
  echo "hardware: ${INSTALL_HARDWARE} (from INSTALL_HARDWARE)"
fi
[[ "$INSTALL_HARDWARE" == "none" ]] && INSTALL_HARDWARE=""

# ---------------------------------------------------------------------------
# Packages needed to get online unaided after the reboot
# ---------------------------------------------------------------------------
echo "packages: started (bootstrap set)"
mapfile -t boot_packages < <(read_pkg_list "$SCRIPT_DIR/packages/packages-bootstrap.txt")

# The kernel may not be plain `linux` (linux-lts, linux-zen, …); DKMS needs the
# headers matching whatever is actually installed.
kernel_headers=()
for pkgbase in /usr/lib/modules/*/pkgbase; do
  [[ -r "$pkgbase" ]] || continue
  kernel_headers+=("$(<"$pkgbase")-headers")
done

hw_packages=()
if [[ -n "$INSTALL_HARDWARE" ]]; then
  hw_file="$SCRIPT_DIR/packages/packages-hardware-${INSTALL_HARDWARE}.txt"
  if [[ -f "$hw_file" ]]; then
    mapfile -t hw_packages < <(read_pkg_list "$hw_file")
  fi
fi

# Full upgrade first: installing with a bare -Sy is the classic partial-upgrade
# trap, and on a fresh install there is nothing to lose by upgrading now.
pacman -Syu --noconfirm
# Headers and the DKMS driver in one transaction, so the build hook (which runs
# at the end of the transaction) finds the headers already in place.
pacman -S --needed --noconfirm "${boot_packages[@]}" \
  ${kernel_headers[0]+"${kernel_headers[@]}"} \
  ${hw_packages[0]+"${hw_packages[@]}"}
echo "packages: finished (bootstrap set)"

# Did the DKMS build actually produce a module? If not, fall back to the
# prebuilt package rather than rebooting into a machine with no Wi-Fi.
if [[ "$INSTALL_HARDWARE" == "macbook" ]]; then
  # wl and the in-kernel Broadcom drivers fight over the same card, and whoever
  # binds first wins. The package ships a blacklist of its own, but this is the
  # difference between having Wi-Fi and not, so make it explicit in /etc.
  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/broadcom-wl.conf <<'EOF'
# Written by bootstrap.sh: this machine has a Broadcom STA chip (BCM4360 etc.)
# driven by wl.ko from broadcom-wl-dkms. Keep the in-kernel drivers off it.
blacklist b43
blacklist b43legacy
blacklist bcma
blacklist ssb
blacklist brcmsmac
blacklist brcmfmac
blacklist brcmutil
EOF

  if compgen -G "/usr/lib/modules/*/updates/dkms/wl.ko*" >/dev/null; then
    echo "wifi: broadcom wl module built by DKMS"
  else
    echo "wifi: DKMS produced no wl module — falling back to prebuilt broadcom-wl" >&2
    pacman -Rdd --noconfirm broadcom-wl-dkms 2>/dev/null || true
    pacman -S --needed --noconfirm broadcom-wl
    echo "wifi: NOTE — prebuilt broadcom-wl breaks on the next kernel update." >&2
    echo "wifi: after that, reinstall it in the same 'pacman -Syu' transaction." >&2
  fi
fi

# ---------------------------------------------------------------------------
# Services that must be on after the reboot
# ---------------------------------------------------------------------------
mkdir -p /etc/iwd
cp "$SCRIPT_DIR/iwd/main.conf" /etc/iwd/main.conf
enable_unit iwd
# usbmuxd is udev/socket-activated on Arch; enable the unit only if one exists.
enable_unit_optional usbmuxd
echo "services: systemd-networkd, systemd-resolved, iwd enabled"

# ---------------------------------------------------------------------------
# Pre-download stage 2, so setup.sh can finish even with no network
# ---------------------------------------------------------------------------
if [[ "${SKIP_CACHE:-0}" != "1" ]]; then
  echo "cache: downloading stage 2 packages into /var/cache/pacman/pkg"
  echo "cache: (several minutes / ~2-3 GB; SKIP_CACHE=1 to skip)"
  mapfile -t stage2_packages < <(read_pkg_list "$SCRIPT_DIR/packages/packages.txt")
  # -w downloads without installing; failures here are not fatal, the cache is
  # an optimisation and stage 2 will simply fetch what is missing.
  pacman -Syuw --noconfirm || echo "cache: upgrade download failed (non-fatal)" >&2
  pacman -Sw --needed --noconfirm "${stage2_packages[@]}" \
    || echo "cache: package download failed (non-fatal)" >&2
  echo "cache: finished"
fi

# ---------------------------------------------------------------------------
# Put the repo where stage 2 can actually reach it.
#
# Cloning to /root/arch is the obvious thing to do from the ISO, but /root is
# mode 750: the normal user cannot read it, and setup.sh refuses to run as root.
# Leave a copy in the user's home, owned by them.
# ---------------------------------------------------------------------------
user_home=$(getent passwd "$existing_user" | cut -d: -f6)
STAGE2_DIR="$SCRIPT_DIR"
if [[ -n "$user_home" && "$SCRIPT_DIR" != "$user_home"/* ]]; then
  dest="$user_home/arch"
  if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
    echo "repo: $dest exists and is not a checkout, leaving it alone" >&2
  else
    echo "repo: copying $SCRIPT_DIR → $dest (owned by $existing_user)"
    mkdir -p "$dest"
    cp -a "$SCRIPT_DIR"/. "$dest"/
    chown -R "$existing_user:$(id -gn "$existing_user")" "$dest"
    STAGE2_DIR="$dest"
  fi
fi

# ---------------------------------------------------------------------------
# Hand DNS back to systemd-resolved for the real boot.
# ---------------------------------------------------------------------------
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# ---------------------------------------------------------------------------
echo ""
echo "=== Stage 1 done ==="
if ((IN_CHROOT)); then
  echo "Networking is configured and will come up on the next boot:"
  echo "  - Ethernet / USB tethering: DHCP automatically"
  echo "  - Wi-Fi: iwctl station wlan0 connect <SSID>"
  if [[ "$INSTALL_HARDWARE" == "macbook" ]]; then
    echo "  - Broadcom wl driver installed for this MacBook's Wi-Fi"
  fi
  echo ""
  echo "Exit the chroot and reboot, then:"
else
  echo "This machine is online. Now:"
fi
echo ""
echo "  su - $existing_user"
echo "  cd $STAGE2_DIR && ./setup.sh"
echo ""
echo "Tethering after reboot: plug the phone in, then enable USB tethering on"
echo "it (iPhone: unlock and tap 'Trust This Computer'). DHCP is automatic."
echo ""
