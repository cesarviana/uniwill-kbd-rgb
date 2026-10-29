#!/bin/bash
# Installs keyboard RGB support for Uniwill/Tongfang laptops:
#   - builds a trimmed tuxedo-drivers (3 modules) through DKMS and loads it at boot
#   - lets members of the 'kbrgb' group change the color without sudo
#   - restores your last color at boot, installs `kbcolor` and a "Keyboard RGB" launcher
#
# Usage:  sudo bash install.sh            (FORCE=1 skips the hardware check)
set -euo pipefail

UPSTREAM_URL=https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers.git
UPSTREAM_TAG=v4.25.0
UPSTREAM_COMMIT=a929f9ce143316b3b18d5f3fbf9cc54f0c1122e2
PKG=kbrgb-tuxedo
VER=${UPSTREAM_TAG#v}
DEST=/usr/src/$PKG-$VER

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }
TARGET_USER="${SUDO_USER:-}"
[ -n "$TARGET_USER" ] && [ "$TARGET_USER" != root ] || { echo "Run it via sudo from your normal user, not from a root shell."; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== 0/7 Compatibility check"
if ! bash "$HERE/check.sh" && [ "${FORCE:-0}" != 1 ]; then
    echo; echo "Aborting. Re-run with FORCE=1 to install anyway."; exit 1
fi
for tool in dkms git make gcc; do
    command -v $tool >/dev/null || { echo "Missing '$tool'. Try: sudo apt install dkms git build-essential linux-headers-\$(uname -r)"; exit 1; }
done
[ -d "/lib/modules/$(uname -r)/build" ] || { echo "Kernel headers for $(uname -r) are missing."; exit 1; }
python3 -c "import gi; gi.require_version('Gtk','3.0')" 2>/dev/null \
    || echo "NOTE: python3-gi/GTK3 not found, the GUI will not start (the 'kbcolor' command still works). Try: sudo apt install python3-gi gir1.2-gtk-3.0"

echo "== 1/7 Fetching tuxedo-drivers $UPSTREAM_TAG"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --quiet --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_URL" "$WORK/tuxedo-drivers"
got="$(git -C "$WORK/tuxedo-drivers" rev-parse HEAD)"
[ "$got" = "$UPSTREAM_COMMIT" ] || { echo "Upstream commit mismatch: expected $UPSTREAM_COMMIT, got $got"; exit 1; }
SRC="$WORK/tuxedo-drivers/src"

echo "== 2/7 DKMS package (uniwill_wmi, tuxedo_keyboard, tuxedo_compatibility_check)"
if dkms status "$PKG/$VER" 2>/dev/null | grep -q "$PKG"; then
    dkms remove "$PKG/$VER" --all || true
fi
rm -rf "$DEST"
mkdir -p "$DEST/src/tuxedo_compatibility_check"
cp "$SRC"/tuxedo_keyboard.c "$SRC"/uniwill_wmi.c "$SRC"/*.h "$DEST/src/"
cp "$SRC"/tuxedo_compatibility_check/*.[ch] "$SRC"/tuxedo_compatibility_check/Kbuild "$DEST/src/tuxedo_compatibility_check/"
cp "$WORK/tuxedo-drivers/LICENSE" "$DEST/"
echo 'obj-y += src/' > "$DEST/Kbuild"
cat > "$DEST/src/Kbuild" <<'EOF'
obj-m += tuxedo_keyboard.o
obj-m += uniwill_wmi.o
obj-y += tuxedo_compatibility_check/
EOF
cat > "$DEST/dkms.conf" <<EOF
PACKAGE_NAME="$PKG"
PACKAGE_VERSION="$VER"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="true"
AUTOINSTALL="yes"

BUILT_MODULE_NAME[0]="tuxedo_keyboard"
BUILT_MODULE_LOCATION[0]="src/"
DEST_MODULE_LOCATION[0]="/updates/dkms"

BUILT_MODULE_NAME[1]="uniwill_wmi"
BUILT_MODULE_LOCATION[1]="src/"
DEST_MODULE_LOCATION[1]="/updates/dkms"

BUILT_MODULE_NAME[2]="tuxedo_compatibility_check"
BUILT_MODULE_LOCATION[2]="src/tuxedo_compatibility_check/"
DEST_MODULE_LOCATION[2]="/updates/dkms"
EOF
dkms add "$PKG/$VER"
dkms install "$PKG/$VER"

echo "== 3/7 Load at boot"
echo uniwill_wmi > /etc/modules-load.d/kbrgb.conf

echo "== 4/7 Group, state dir and udev rule"
getent group kbrgb >/dev/null || groupadd --system kbrgb
usermod -aG kbrgb "$TARGET_USER"
install -d -m 2775 -o root -g kbrgb /var/lib/kbrgb
cat > /etc/udev/rules.d/90-kbrgb.rules <<'EOF'
# Let members of 'kbrgb' control the keyboard RGB LED and restore the saved color.
SUBSYSTEM=="leds", KERNEL=="rgb:kbd_backlight", ACTION=="add", \
  RUN+="/bin/sh -c 'chgrp kbrgb /sys%p/brightness /sys%p/multi_intensity; chmod g+w /sys%p/brightness /sys%p/multi_intensity'", \
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="kbrgb-restore.service"
EOF

echo "== 5/7 Restore service"
cat > /etc/systemd/system/kbrgb-restore.service <<'EOF'
[Unit]
Description=Restore keyboard RGB color

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kbcolor --restore
EOF
systemctl daemon-reload

echo "== 6/7 CLI and launcher"
install -m 0755 "$HERE/kbcolor" /usr/local/bin/kbcolor
cat > /usr/share/applications/kbrgb.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Keyboard RGB
Comment=Change the keyboard backlight color
Exec=/usr/local/bin/kbcolor --gui
Icon=preferences-desktop-keyboard
Categories=Settings;HardwareSettings;
Terminal=false
EOF

echo "== 7/7 Loading the DKMS-built modules now"
rmmod uniwill_wmi tuxedo_keyboard tuxedo_compatibility_check 2>/dev/null || true
depmod -a
modprobe uniwill_wmi
udevadm control --reload
udevadm trigger --action=add --subsystem-match=leds

echo
dkms status "$PKG"
if [ -e /sys/class/leds/rgb:kbd_backlight ]; then
    echo "OK: /sys/class/leds/rgb:kbd_backlight exists."
else
    echo "WARNING: the driver loaded but no rgb:kbd_backlight LED appeared."
    echo "         Your keyboard may not be a 1-zone RGB model. Check: sudo dmesg | grep -i -E 'tuxedo|uniwill'"
fi
echo
echo "Done. Log out and back in (or reboot) so '$TARGET_USER' picks up the 'kbrgb' group."
echo "Then run:  kbcolor purple   or open 'Keyboard RGB' from your app launcher."
