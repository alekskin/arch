# Arch → sway desktop bootstrap

Turn a **minimal Arch** install into this machine’s sway desktop (packages, services, and [dotfiles](https://github.com/alekskin/dotfiles)).

## What you need first

From `archinstall` or a manual install:

1. Bootable Arch system
2. A **normal user** (archinstall: *User account* → add a superuser)

This repo does **not** replace partitioning, bootloader, or creating the user.
Networking is handled for you by stage 1 below.

## Install (two stages)

A fresh install has no networking — the live ISO's connection isn't carried
over — so this runs in two parts.

### Stage 1 — as root, right after install

Brings the machine online (wired DHCP, or helps you connect Wi‑Fi) and
installs `sudo` + `git`.

```bash
# as root, with the repo on the machine
./bootstrap.sh
```

Getting the repo there with no network yet: clone it from the **live ISO**
(which does have network) before rebooting —
`git clone https://github.com/alekskin/arch.git /mnt/root/arch` — or plug in
Ethernet and `pacman -Sy git` first.

### Stage 2 — as your user, after logging in

Installs every package, service, and the desktop. Must **not** run as root.

```bash
su - <username>
git clone https://github.com/alekskin/arch.git ~/arch
cd ~/arch
./setup.sh
sudo reboot
```

At the **SDDM** login (minimal theme), pick session **Sway** and log in.

### Interactive prompts

When you run `./setup.sh` in a terminal it asks:

1. Install **AUR** packages (yay + `localsend-bin`, …)? **[Y/n]**
2. Install/stow **dotfiles**? **[Y/n]**  
   - If yes and dotfiles are missing: git URL + directory
3. **Hardware extras**:
   - `1) none` (default)
   - `2) macbook` — Broadcom Wi‑Fi (`broadcom-wl`)
   - `3) amd` — AMD GPU stack (`vulkan-radeon`, VA-API, `amdgpu`, `amd-ucode`)
4. **Fingerprint** auth for sudo/polkit? **[y/N]** — only say yes on a machine
   with a sensor; it enrolls a finger (needs you present). Falls through to
   password, so it can't lock you out.
5. Confirm and continue

Defaults are the usual full install (AUR + dotfiles, no hardware extras).

### Non-interactive / automation

Env vars skip prompts for those choices:

| Variable | Meaning |
|----------|---------|
| `DOTFILES_DIR` | Path to dotfiles (default `~/dotfiles`) |
| `DOTFILES_REPO` | Git URL if clone needed |
| `INSTALL_HARDWARE=macbook` | MacBook Wi‑Fi packages |
| `INSTALL_HARDWARE=amd` | AMD GPU/CPU packages |
| `SKIP_DOTFILES=1` | Packages/services only |
| `SKIP_AUR=1` | Skip yay + AUR |
| `SETUP_FINGERPRINT=1` | Enroll + wire fingerprint (needs a sensor) |

Example:

```bash
SKIP_AUR=1 INSTALL_HARDWARE=macbook ./setup.sh
```

## What `setup.sh` does

1. `pacman -Syu` + install `packages/packages.txt`
2. Optional hardware package file
3. Bootstrap **yay** (`yay-bin`) and install `packages/packages-aur.txt`
4. Systemd: logind power-key, **systemd-resolved**, **iwd**, **bluetooth**, **sddm**, **docker**, **tailscaled**, **power-profiles-daemon**
5. Clone/stow **dotfiles** via `dotfiles/install.sh`
6. `xdg-user-dirs-update` + MIME defaults (`config/mimetypes.sh`)
7. Generate an SSH key at `~/.ssh/id_github` if missing
8. Optional: **fingerprint** enrollment + PAM (`config/fingerprint-setup.sh`)

## Repo layout

```text
arch/
  setup.sh
  packages/
    packages.txt                 # official repos
    packages-aur.txt             # AUR (localsend-bin, …)
    packages-hardware-macbook.txt
    packages-hardware-amd.txt
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
