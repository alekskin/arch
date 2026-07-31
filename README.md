# Arch → sway desktop bootstrap

Turn a **minimal Arch** install into this machine’s sway desktop (packages, services, and [dotfiles](https://github.com/BabkinAleksandr/dotfiles)).

## What you need first

From `archinstall` or a manual install:

1. Bootable Arch system with a **normal user** + **sudo**
2. **Network** working (Ethernet, or Wi‑Fi already configured for the install)
3. `git` available (`pacman -S git`)

This repo does **not** replace partitioning, bootloader, or creating the user.

## Quick start (bare metal)

```bash
# As your user
sudo pacman -Syu --needed git
git clone https://github.com/BabkinAleksandr/arch.git ~/arch
git clone https://github.com/BabkinAleksandr/dotfiles.git ~/dotfiles   # optional; setup can clone it

cd ~/arch
./setup.sh
sudo reboot
```

At **SDDM**, pick session **Sway**.

### MacBook (Broadcom Wi‑Fi)

```bash
INSTALL_HARDWARE=macbook ./setup.sh
```

Installs `broadcom-wl` + `linux-headers` from `packages/packages-hardware-macbook.txt`.

### Environment overrides

| Variable | Meaning |
|----------|---------|
| `DOTFILES_DIR` | Path to dotfiles (default `~/dotfiles`) |
| `DOTFILES_REPO` | Git URL if clone needed (default GitHub dotfiles) |
| `INSTALL_HARDWARE=macbook` | Extra hardware packages |
| `SKIP_DOTFILES=1` | Packages/services only |
| `SKIP_AUR=1` | Skip yay + AUR |

## What `setup.sh` does

1. `pacman -Syu` + install `packages/packages.txt`
2. Optional hardware package file
3. Bootstrap **yay** (`yay-bin`) and install `packages/packages-aur.txt`
4. Systemd: logind power-key, **systemd-resolved**, **iwd**, **bluetooth**, **sddm**, **docker**, **tailscaled**, **power-profiles-daemon**
5. Clone/stow **dotfiles** via `dotfiles/install.sh`
6. `xdg-user-dirs-update` + MIME defaults (`config/mimetypes.sh`)

## Repo layout

```text
arch/
  setup.sh
  packages/
    packages.txt                 # official repos
    packages-aur.txt             # AUR (localsend-bin, …)
    packages-hardware-macbook.txt
  config/mimetypes.sh
  iwd/main.conf
  systemd/ignore-power-key.conf
  README.md
```

Desktop config (sway, waybar, bash, …) lives in the **dotfiles** repo, not here.

## After first login

| Task | How |
|------|-----|
| Wi‑Fi | `Super+Ctrl+W` or `impala` |
| App launcher | `Super+D` |
| System menu | `Super+Escape` |
| Tailscale | `sudo tailscale up` |
| Docker group | log out/in once after setup |
| Dotfiles only | `~/dotfiles/install.sh` |

## Fresh machine checklist

- [ ] Arch installed, user + sudo, network up  
- [ ] `./setup.sh` completed without errors  
- [ ] Rebooted into SDDM → **Sway**  
- [ ] Waybar / terminal / Super+D work  
- [ ] (MacBook) Wi‑Fi via `broadcom-wl` if needed  

## Not in scope

- Full theming / Omarchy theme switcher  
- NVIDIA-specific stacks (add packages yourself if needed)  
- Replacing archinstall / disk layout  
