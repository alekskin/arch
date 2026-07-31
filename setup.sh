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
# Interactive prompts choose optional steps when run in a terminal.
# Env vars still override (useful for automation / non-interactive):
#   DOTFILES_DIR, DOTFILES_REPO, INSTALL_HARDWARE, SKIP_DOTFILES, SKIP_AUR

set -euo pipefail

echo "=== Arch setup (bare → sway desktop) ==="

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/BabkinAleksandr/dotfiles.git}"

# ---------------------------------------------------------------------------
# Interactive options (skipped if env already set, or stdin is not a TTY)
# ---------------------------------------------------------------------------
ask_yes_no() {
  # ask_yes_no "Question?" default_yes|default_no → sets REPLY to y or n
  local prompt=$1
  local def=${2:-default_yes}
  local hint yn
  if [[ "$def" == "default_no" ]]; then
    hint="y/N"
  else
    hint="Y/n"
  fi

  if [[ ! -t 0 ]]; then
    # Non-interactive: keep default
    if [[ "$def" == "default_no" ]]; then
      REPLY=n
    else
      REPLY=y
    fi
    return 0
  fi

  while true; do
    read -r -p "$prompt [$hint] " yn || yn=""
    yn=${yn:-}
    case "$yn" in
      "")
        if [[ "$def" == "default_no" ]]; then REPLY=n; else REPLY=y; fi
        return 0
        ;;
      y|Y|yes|YES) REPLY=y; return 0 ;;
      n|N|no|NO) REPLY=n; return 0 ;;
      *) echo "  Please answer y or n." ;;
    esac
  done
}

prompt_options() {
  echo ""
  echo "Optional steps (Enter accepts the default):"
  echo ""

  # AUR / yay
  if [[ -z "${SKIP_AUR+x}" ]]; then
    ask_yes_no "  Install AUR packages (yay + localsend-bin, etc.)?" default_yes
    if [[ "$REPLY" == "y" ]]; then
      SKIP_AUR=0
    else
      SKIP_AUR=1
    fi
  fi

  # Dotfiles
  if [[ -z "${SKIP_DOTFILES+x}" ]]; then
    ask_yes_no "  Install/stow dotfiles (sway, waybar, bash, …)?" default_yes
    if [[ "$REPLY" == "y" ]]; then
      SKIP_DOTFILES=0
      if [[ -t 0 ]] && [[ ! -d "$DOTFILES_DIR/.git" && ! -f "$DOTFILES_DIR/install.sh" ]]; then
        read -r -p "  Dotfiles git URL [$DOTFILES_REPO]: " url || url=""
        if [[ -n "${url:-}" ]]; then
          DOTFILES_REPO=$url
        fi
        read -r -p "  Dotfiles directory [$DOTFILES_DIR]: " dir || dir=""
        if [[ -n "${dir:-}" ]]; then
          DOTFILES_DIR=$dir
        fi
      fi
    else
      SKIP_DOTFILES=1
    fi
  fi

  # Hardware profile
  if [[ -z "${INSTALL_HARDWARE+x}" ]]; then
    echo ""
    echo "  Hardware extras:"
    echo "    1) none (default)"
    echo "    2) macbook  (broadcom-wl + linux-headers)"
    echo "    3) amd      (vulkan-radeon, VA-API, amdgpu, amd-ucode)"
    if [[ -t 0 ]]; then
      read -r -p "  Choice [1]: " hw || hw=""
    else
      hw=1
    fi
    case "${hw:-1}" in
      2|macbook|MacBook|MACBOOK) INSTALL_HARDWARE=macbook ;;
      3|amd|AMD) INSTALL_HARDWARE=amd ;;
      *) INSTALL_HARDWARE=none ;;
    esac
  fi

  # Normalize empty / none
  [[ "${INSTALL_HARDWARE:-none}" == "none" ]] && INSTALL_HARDWARE=""

  echo ""
  echo "Selections:"
  echo "  AUR packages:     $([[ "${SKIP_AUR:-0}" == "1" ]] && echo no || echo yes)"
  echo "  Dotfiles stow:    $([[ "${SKIP_DOTFILES:-0}" == "1" ]] && echo no || echo yes)"
  if [[ "${SKIP_DOTFILES:-0}" != "1" ]]; then
    echo "  Dotfiles dir:     $DOTFILES_DIR"
    echo "  Dotfiles repo:    $DOTFILES_REPO"
  fi
  echo "  Hardware extras:  ${INSTALL_HARDWARE:-none}"
  echo ""

  if [[ -t 0 ]]; then
    ask_yes_no "Continue with installation?" default_yes
    if [[ "$REPLY" != "y" ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
  echo ""
}

prompt_options

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

if [[ -n "${INSTALL_HARDWARE:-}" ]]; then
  hw_file="./packages/packages-hardware-${INSTALL_HARDWARE}.txt"
  if [[ -f "$hw_file" ]]; then
    echo "packages-hardware-${INSTALL_HARDWARE}: started"
    mapfile -t hw_packages < <(read_pkg_list "$hw_file")
    if ((${#hw_packages[@]} > 0)); then
      sudo pacman -S --needed --noconfirm "${hw_packages[@]}"
    fi
    echo "packages-hardware-${INSTALL_HARDWARE}: finished"
  else
    echo "packages-hardware: no file $hw_file (ignored)" >&2
  fi
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
echo "Hardware later:  INSTALL_HARDWARE=amd|macbook ./setup.sh  (or re-run and choose at prompt)"
echo "Dotfiles only:   $DOTFILES_DIR/install.sh"
