# uniwill-kbd-rgb

Keyboard RGB backlight on Linux for **Uniwill / Tongfang-based laptops that are not sold by TUXEDO**, such as Avell, and probably other rebrands. The keyboard lights up in Windows and stays white (or dark) on Linux, and no RGB tool (OpenRGB, ckb-next, ...) can see it because it is not a USB or HID device. It is controlled by the laptop's embedded controller (EC) through ACPI/WMI.

This project is a small installer around the open-source [`tuxedo-drivers`](https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers), plus the missing user-facing parts:

- a **DKMS** package with only the 3 modules needed (rebuilds on kernel updates, loads at boot)
- **no `sudo` needed** to change colors (udev rule + `kbrgb` group)
- a **GUI color picker** ("Keyboard RGB" in your app launcher)
- a **`kbcolor` command** (`kbcolor purple`, `kbcolor ff8800`, `kbcolor -b 2`)
- your **last color is restored at boot**

> **Not affiliated with TUXEDO Computers, Avell, or Uniwill.** The kernel driver is theirs (GPL-2.0+); this repo only packages and wraps it. See [Credits](#credits).

## Is my laptop supported?

Run the read-only check (no root needed):

```bash
git clone https://github.com/cesarviana/uniwill-kbd-rgb.git
cd uniwill-kbd-rgb
bash check.sh
```

It looks for the six Uniwill WMI interfaces (`ABBC0F6D`–`ABBC0F72`). If all are present, your machine is a candidate. That is **not a guarantee**: the EC must also report a RGB keyboard. If it doesn't, the installer tells you at the end and nothing is harmed.

Not for you if:
- your keyboard is a **USB** device (check `lsusb`; e.g. ITE `048d:xxxx`, SteelSeries, Razer, Corsair). Look at OpenRGB or `tuxedo-drivers`' `ite_829x` instead.
- your laptop is a **Clevo** (System76, Schenker XMG, ...). Different interface.

### Tested on

| Laptop | Distro / kernel | Result |
|---|---|---|
| Avell A52 HYB (board `Avell A52 HYB`, 1-zone RGB) | Pop!_OS 24.04 (COSMIC), kernel 7.2.6 | works |

Got it working (or not) on another model? Please open an issue with your `bash check.sh` output and the result, so this table can grow.

## Install

Requirements: Debian/Ubuntu-family distro (tested on Pop!_OS 24.04), kernel headers for your running kernel, `dkms`, `git`, `build-essential`, and for the GUI `python3-gi` + `gir1.2-gtk-3.0`.

```bash
sudo apt install dkms git build-essential linux-headers-$(uname -r) python3-gi gir1.2-gtk-3.0
sudo bash install.sh
```

Then **log out and back in** (or reboot) so your user joins the `kbrgb` group.

The installer checks your hardware first and downloads `tuxedo-drivers` **v4.25.0**, verifying it matches a pinned commit hash. Read it before running it; it is a single short shell script.

### Secure Boot

If Secure Boot is enabled, the DKMS modules must be signed and enrolled, or the kernel will refuse to load them (`Key was rejected by service`). On Ubuntu-family systems DKMS will offer to create a Machine Owner Key (MOK) and ask you for a one-time password; reboot and confirm it in the blue MokManager screen. Or disable Secure Boot. `bash check.sh` shows your current state.

## Use

**GUI:** open **Keyboard RGB** from your app launcher (or run `kbcolor --gui`). Pick a color, drag the brightness slider. Changes apply live and are saved.

**Command line:**

```bash
kbcolor purple          # named color: white red orange amber yellow lemon lime green mint teal cyan sky blue indigo purple magenta pink hotpink
kbcolor ff8800          # hex (a leading # works too)
kbcolor 0 120 255       # r g b, 0-255
kbcolor -b 2            # brightness 0-4 (0 = off)
kbcolor --off
kbcolor                 # show usage and current values
```

Or write the kernel interface directly:

```bash
echo "255 0 0" | sudo tee /sys/class/leds/rgb:kbd_backlight/multi_intensity
echo 4         | sudo tee /sys/class/leds/rgb:kbd_backlight/brightness
```

The Fn brightness keys keep working.

## Limitations

- **One color for the whole keyboard.** This hardware class has a single RGB zone. No per-key colors, no animations/effects.
- Brightness has 5 steps (0-4).
- GUI is GTK3; it was written for and tested on COSMIC/Wayland only. Reports for GNOME/KDE/X11 are welcome.

## Uninstall

```bash
sudo bash uninstall.sh
```

## How it works

1. `uniwill_wmi` / `tuxedo_keyboard` (from `tuxedo-drivers`) read the EC feature bits. On a 1-zone RGB keyboard they register a kernel multicolor LED, `/sys/class/leds/rgb:kbd_backlight`, with `multi_intensity` (R G B) and `brightness` files.
2. A udev rule makes those two files writable by group `kbrgb`, and triggers `kbrgb-restore.service`.
3. `kbcolor` writes to those files and saves the choice in `/var/lib/kbrgb/state.json`, which the service re-applies at boot.

The upstream driver only whitelists TUXEDO models for some features, but it detects the keyboard type from the EC for the RGB path and skips its DMI-name check on Intel 12th-gen and older CPUs. That is why it works on other brands' Uniwill machines, but newer CPUs might need an upstream change. If `check.sh` passes yet no LED appears, open an issue with `sudo dmesg | grep -i -E 'tuxedo|uniwill'`.

## Safety

This writes to your laptop's embedded controller through the vendor's WMI interface, using a driver written for TUXEDO models. It worked for the author, but **you use it at your own risk**. It does not flash firmware. `sudo bash uninstall.sh` removes it and a reboot returns everything to the default.

## Credits

- [`tuxedo-drivers`](https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers) by TUXEDO Computers GmbH, GPL-2.0+. All the hard work is theirs.
- Everything in this repo (scripts, `kbcolor`) is MIT-licensed, see [LICENSE](LICENSE). Nothing from `tuxedo-drivers` is copied into the repo; the installer downloads it.
