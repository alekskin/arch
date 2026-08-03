#!/bin/bash
# Enable fingerprint authentication (fprintd) for sudo and polkit, then enroll
# a finger. Run as your normal user on a machine that HAS a fingerprint sensor:
#
#   bash ~/arch/config/fingerprint-setup.sh
#
# Idempotent; backs up each PAM file before editing. Uses `sufficient`, so your
# password still works if the finger fails or no print is enrolled — you cannot
# lock yourself out. Not part of setup.sh because enrolling needs the sensor and
# your finger (same reason Omarchy makes it a separate `setup fingerprint` step).
set -euo pipefail

PAM_LINE='auth      sufficient  pam_fprintd.so'
stamp=$(date +%Y%m%d-%H%M%S)

echo "== fingerprint setup =="

# 1) Package
if ! command -v fprintd-enroll >/dev/null; then
  echo "Installing fprintd…"
  sudo pacman -S --needed --noconfirm fprintd
fi

# 2) Sensor present? (fprintd-list prints nothing on stdout when there's no device)
if [[ -z "$(fprintd-list "$USER" 2>/dev/null)" ]]; then
  echo "No fingerprint sensor detected."
  echo "If your sensor is brand-new, try the AUR package 'libfprint-git' and re-run"
  echo "(use 'lsusb' to identify it)."
  exit 1
fi

# 3) PAM: add pam_fprintd as the first auth method (sufficient = falls back to
#    password). Idempotent + backed up.
add_pam() { # $1 = pam file
  local f=$1
  if sudo grep -q 'pam_fprintd.so' "$f" 2>/dev/null; then
    echo "  $f: already configured"
    return 0
  fi
  sudo cp "$f" "$f.bak.$stamp"
  sudo sed -i "0,/^auth/s//$PAM_LINE\n&/" "$f"
  echo "  $f: added pam_fprintd (backup: $f.bak.$stamp)"
}

echo "Configuring PAM…"
add_pam /etc/pam.d/sudo
if [[ -f /etc/pam.d/polkit-1 ]]; then
  add_pam /etc/pam.d/polkit-1
else
  echo "  /etc/pam.d/polkit-1: creating with pam_fprintd"
  sudo tee /etc/pam.d/polkit-1 >/dev/null <<'EOF'
auth      sufficient pam_fprintd.so
auth      include    system-auth
account   include    system-auth
password  include    system-auth
session   include    system-auth
EOF
fi

# 4) Enroll + verify
echo
echo "Enrolling a finger — keep touching the sensor until it completes…"
sudo fprintd-enroll "$USER"
echo
echo "Verifying…"
fprintd-verify || echo "(verify failed — re-run to enroll again)"

echo
echo "Done. Fingerprint now works for: sudo, and polkit (GUI auth prompts)."
echo "Not covered: the sway lock screen (swaylock is password-only) and the"
echo "SDDM login (left on password to avoid greeter quirks)."
