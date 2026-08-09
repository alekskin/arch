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
over, and the drivers/daemons that made it work on the ISO aren't in a bare
`pacstrap` install either — so this runs in two parts.

### Stage 1 — as root, from the live ISO (recommended)

Run it **before the first reboot, while the ISO is still online**. That is the
only moment when the machine can download the things it needs in order to get
online by itself later: the Broadcom Wi-Fi driver, `usbmuxd` for iPhone
tethering, `iwd`, `sudo`, `git`.

```bash
# in the live ISO, network up, system already installed to /mnt
pacman -Sy git
git clone https://github.com/alekskin/arch.git /mnt/root/arch
arch-chroot /mnt /root/arch/bootstrap.sh
reboot
```

It detects the chroot: units are enabled for the next boot rather than started,
and the network is taken from the ISO. It also pre-downloads every stage 2
package into `/var/cache/pacman/pkg`, so `setup.sh` can finish even if the
machine ends up offline (`SKIP_CACHE=1` to skip that, `INSTALL_HARDWARE=…` to
override Wi-Fi hardware detection).

### Stage 1 — alternative: on the booted system

Same script, run as root on a machine that already has *some* way online. It
brings up wired/tether DHCP, or walks you through `iwctl` for Wi-Fi.

```bash
./bootstrap.sh
```

If it can't reach the network and `iwd`/the Wi-Fi driver aren't installed,
there is nothing it can do offline — boot the ISO and use the chroot flow above.

#### Getting the repo onto the machine with no network

Chicken-and-egg: cloning needs network, and stage 1 is what sets network up.
Pick whichever applies:

- **Clone from the live ISO before rebooting** — this is the chroot flow above,
  and it's why it's the recommended one.
- **Wired / VM:** plug in Ethernet, then `pacman -Sy git` and clone normally.
- **Stuck without either:** bring wired DHCP up by hand — all of this is built
  into systemd, so it downloads nothing — then clone:

  ```bash
  printf '[Match]\nName=en* eth* usb*\n\n[Network]\nDHCP=yes\n' \
    > /etc/systemd/network/20-wired.network
  systemctl enable --now systemd-networkd systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  pacman -Sy git
  ```

  (Running `bootstrap.sh` afterwards is still fine — it is idempotent.)

### Networking after the reboot

| Uplink | What happens |
|--------|--------------|
| Ethernet | DHCP automatically (`20-wired.network`) |
| USB tethering | DHCP automatically (`25-tether.network` matches `ipheth`/RNDIS/NCM). Plug in, enable tethering on the phone; on iPhone unlock and *Trust This Computer* |
| Wi-Fi | `iwctl station wlan0 connect <SSID>` |

If Wi-Fi won't associate on a Broadcom `wl` card (iwd is known to be picky with
that driver), the fallback is installed but not enabled:

```bash
sudo systemctl disable --now iwd
sudo systemctl enable --now wpa_supplicant@wlan0 dhcpcd
```

### Stage 2 — as your user, after logging in

Installs every package, service, and the desktop. Must **not** run as root.

Stage 1 leaves a copy of this repo at `~/arch`, owned by your user — cloning it
to `/root/arch` from the ISO is the natural thing to do, but `/root` is mode
750, so your user could not read it there.

```bash
su - <username>
cd ~/arch          # already there, courtesy of bootstrap.sh
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
   - `2) macbook` — Broadcom Wi‑Fi (`broadcom-wl-dkms`); normally already installed by stage 1
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
  bootstrap.sh                   # stage 1, root (chroot-aware)
  setup.sh                       # stage 2, your user
  packages/
    packages-bootstrap.txt       # offline-critical set (stage 1)
    packages.txt                 # official repos
    packages-aur.txt             # AUR (localsend-bin, …)
    packages-hardware-macbook.txt
    packages-hardware-amd.txt
  config/mimetypes.sh
  iwd/main.conf
  systemd/20-wired.network       # Ethernet DHCP
  systemd/25-tether.network      # USB tethering DHCP
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
- [ ] (MacBook) Wi‑Fi works — `broadcom-wl-dkms` installed by stage 1  

## Not in scope

- Full theming / Omarchy theme switcher  
- NVIDIA-specific stacks (add packages yourself if needed)  
- Replacing archinstall / disk layout  
