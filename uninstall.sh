#!/bin/bash
# Removes everything install.sh set up.  Run with:  sudo bash ~/kbrgb-setup/uninstall.sh
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

rmmod uniwill_wmi tuxedo_keyboard tuxedo_compatibility_check 2>/dev/null
dkms remove kbrgb-tuxedo/4.25.0 --all 2>/dev/null
rm -rf /usr/src/kbrgb-tuxedo-4.25.0 /var/lib/kbrgb
rm -f /etc/modules-load.d/kbrgb.conf /etc/udev/rules.d/90-kbrgb.rules \
      /etc/systemd/system/kbrgb-restore.service /usr/local/bin/kbcolor \
      /usr/share/applications/kbrgb.desktop
systemctl daemon-reload
udevadm control --reload
depmod -a
groupdel kbrgb 2>/dev/null
echo "Removed."
