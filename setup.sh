#!/bin/bash
# Bootstrap a bare Arch install toward this sway desktop.
#
# Prerequisites (from archiso / archinstall):
#   - non-root user with sudo
#   - working network (ethernet or already-configured Wi-Fi)
#   - this repo cloned, e.g. ~/arch
#
# Usage:
#   cd ~/arch && ./setup.sh
#
# Optional env:
#   DOTFILES_DIR=~/dotfiles          # default: $HOME/dotfiles
#   DOTFILES_REPO=git@github.com:BabkinAleksandr/dotfiles.git
#   INSTALL_HARDWARE=macbook         # also install packages-hardware-macbook.txt
#   SKIP_DOTFILES=1                  # packages/services only
#   SKIP_AUR=1                       # skip yay + AUR packages

set -euo pipefail

echo "=== Arch setup (bare → sway desktop) ==="

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/BabkinAleksandr/dotfiles.git}"

read_pkg_list() {
  sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$1"
}

target_user() {
  local u="${SUDO_USER:-$USER}"
  if [[ "$u" == "root" ]]; then
    u=$(logname 2>/dev/null || true)
  fi
  printf '%s' "${u:-}"
}

run_as_user() {
  local u
  u=$(target_user)
  if [[ -n "$u" && "$u" != "root" ]] && id "$u" &>/dev/null; then
    sudo -u "$u" --preserve-env=HOME,XDG_RUNTIME_DIR,DBUS_SESSION_BUS_ADDRESS "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
echo "packages: started"
mapfile -t packages < <(read_pkg_list ./packages/packages.txt)
if ((${#packages[@]} == 0)); then
  echo "packages: error — no packages in ./packages/packages.txt" >&2
  exit 1
fi

# Full upgrade path (Arch-recommended); then ensure our set is present
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm "${packages[@]}"
echo "packages: finished"

if [[ "${INSTALL_HARDWARE:-}" == "macbook" && -f ./packages/packages-hardware-macbook.txt ]]; then
  echo "packages-hardware-macbook: started"
  mapfile -t hw_packages < <(read_pkg_list ./packages/packages-hardware-macbook.txt)
  if ((${#hw_packages[@]} > 0)); then
    sudo pacman -S --needed --noconfirm "${hw_packages[@]}"
  fi
  echo "packages-hardware-macbook: finished"
fi

# ---------------------------------------------------------------------------
# yay + AUR
# ---------------------------------------------------------------------------
install_yay() {
  if command -v yay >/dev/null; then
    echo "yay: already installed"
    return 0
  fi

  echo "yay: bootstrapping from AUR (yay-bin)…"
  sudo pacman -S --needed --noconfirm base-devel git

  local build_user
  build_user=$(target_user)
  if [[ -z "$build_user" || "$build_user" == "root" ]]; then
    echo "yay: error — need a non-root user to run makepkg" >&2
    return 1
  fi

  local tmp
  tmp=$(mktemp -d /tmp/yay-bin.XXXXXX)
  sudo -u "$build_user" git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp"
  (cd "$tmp" && sudo -u "$build_user" makepkg -si --noconfirm)
  rm -rf "$tmp"

  command -v yay >/dev/null || {
    echo "yay: error — install failed" >&2
    return 1
  }
  echo "yay: installed $(yay --version | head -1)"
}

if [[ "${SKIP_AUR:-0}" != "1" ]]; then
  echo "yay: started"
  install_yay
  echo "yay: finished"

  if [[ -f ./packages/packages-aur.txt ]]; then
    mapfile -t aur_packages < <(read_pkg_list ./packages/packages-aur.txt)
    if ((${#aur_packages[@]} > 0)) && command -v yay >/dev/null; then
      echo "packages-aur: started"
      build_user=$(target_user)
      if [[ -n "$build_user" && "$build_user" != "root" ]]; then
        sudo -u "$build_user" yay -S --needed --noconfirm "${aur_packages[@]}"
      else
        yay -S --needed --noconfirm "${aur_packages[@]}"
      fi
      echo "packages-aur: finished"
    fi
  fi
else
  echo "yay/AUR: skipped (SKIP_AUR=1)"
fi

# ---------------------------------------------------------------------------
# systemd / network
# ---------------------------------------------------------------------------
echo "systemd: started"
sudo mkdir -p /etc/systemd/logind.conf.d
sudo cp ./systemd/ignore-power-key.conf /etc/systemd/logind.conf.d/ignore-power-key.conf
sudo systemctl restart systemd-logind
echo "systemd: finished"

echo "dns: started"
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
echo "dns: finished"

echo "iwd: started"
sudo mkdir -p /etc/iwd
sudo cp ./iwd/main.conf /etc/iwd/main.conf
sudo systemctl enable --now iwd
sudo systemctl disable --now NetworkManager wpa_supplicant 2>/dev/null || true
echo "iwd: finished"

echo "bluetooth: started"
sudo systemctl enable --now bluetooth 2>/dev/null || true
echo "bluetooth: finished"

echo "sddm: started"
sudo systemctl enable sddm
echo "sddm: finished"

echo "docker: started"
sudo systemctl enable --now docker
u=$(target_user)
if [[ -n "$u" && "$u" != "root" ]]; then
  sudo usermod -aG docker "$u"
  echo "docker: added $u to group 'docker' (log out/in to apply)"
fi
echo "docker: finished"

echo "tailscale: started"
sudo systemctl enable --now tailscaled
if ! lsmod | grep -q '^tun\b'; then
  sudo modprobe tun 2>/dev/null || true
fi
echo "tailscale: finished"

echo "power-profiles: started"
sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
echo "power-profiles: finished"

# ---------------------------------------------------------------------------
# Dotfiles
# ---------------------------------------------------------------------------
if [[ "${SKIP_DOTFILES:-0}" != "1" ]]; then
  echo "dotfiles: started"
  if [[ ! -d "$DOTFILES_DIR/.git" && ! -f "$DOTFILES_DIR/install.sh" ]]; then
    echo "dotfiles: cloning $DOTFILES_REPO → $DOTFILES_DIR"
    u=$(target_user)
    parent=$(dirname "$DOTFILES_DIR")
    sudo -u "${u:-$USER}" mkdir -p "$parent"
    if [[ -n "$u" && "$u" != "root" ]]; then
      sudo -u "$u" git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    else
      git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
  fi

  if [[ -x "$DOTFILES_DIR/install.sh" ]]; then
    echo "dotfiles: running install.sh (stow)"
    if [[ -n "$(target_user)" && "$(target_user)" != "root" ]]; then
      sudo -u "$(target_user)" bash "$DOTFILES_DIR/install.sh"
    else
      bash "$DOTFILES_DIR/install.sh"
    fi
  elif [[ -d "$DOTFILES_DIR" ]]; then
    echo "dotfiles: warning — no install.sh at $DOTFILES_DIR" >&2
  else
    echo "dotfiles: warning — missing $DOTFILES_DIR (set DOTFILES_DIR or DOTFILES_REPO)" >&2
  fi
  echo "dotfiles: finished"
else
  echo "dotfiles: skipped (SKIP_DOTFILES=1)"
fi

# ---------------------------------------------------------------------------
# User dirs + MIME defaults
# ---------------------------------------------------------------------------
echo "user-dirs: started"
run_as_user xdg-user-dirs-update 2>/dev/null || xdg-user-dirs-update 2>/dev/null || true
echo "user-dirs: finished"

echo "mimetypes: started"
if [[ -f "$SCRIPT_DIR/config/mimetypes.sh" ]]; then
  run_as_user bash "$SCRIPT_DIR/config/mimetypes.sh" || bash "$SCRIPT_DIR/config/mimetypes.sh"
fi
echo "mimetypes: finished"

# ---------------------------------------------------------------------------
echo ""
echo "=== Done ==="
echo "Next:"
echo "  1. reboot"
echo "  2. at SDDM, choose session: Sway"
echo "  3. Wi-Fi: Super+Ctrl+W or: impala"
echo "  4. Tailscale: sudo tailscale up"
echo "  5. if docker group was added: log out/in once"
echo ""
echo "MacBook Wi-Fi driver: INSTALL_HARDWARE=macbook ./setup.sh"
echo "Dotfiles only:        $DOTFILES_DIR/install.sh"
