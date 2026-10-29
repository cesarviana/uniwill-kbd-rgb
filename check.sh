#!/bin/bash
# Read-only compatibility check. Needs no root.  Usage: bash check.sh
# Exit status: 0 = looks like a supported Uniwill machine, 1 = not detected.

ok=0
dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null; }

echo "Machine : $(dmi sys_vendor) / $(dmi product_name)  (board: $(dmi board_name))"
echo "Kernel  : $(uname -r)"

# The Uniwill EC driver needs all six of these WMI interfaces.
missing=0
for suffix in 6D 6E 6F 70 71 72; do
    guid="ABBC0F${suffix}-8EA1-11D1-00A0-C90629100000"
    if [ -e "/sys/bus/wmi/devices/$guid" ]; then
        echo "WMI     : $guid  present"
    else
        echo "WMI     : $guid  MISSING"
        missing=1
    fi
done
[ $missing -eq 0 ] && ok=1

if [ -e /sys/class/leds/rgb:kbd_backlight ]; then
    echo "LED     : rgb:kbd_backlight already exists (driver is loaded)"
fi

if command -v mokutil >/dev/null 2>&1; then
    echo "SecBoot : $(mokutil --sb-state 2>&1 | head -1)"
elif [ -r /sys/kernel/security/lockdown ]; then
    echo "Lockdown: $(cat /sys/kernel/security/lockdown)  (unsigned modules only load when this is [none])"
fi

[ -d "/lib/modules/$(uname -r)/build" ] && echo "Headers : found" || echo "Headers : MISSING (install linux-headers for $(uname -r))"
for tool in dkms git make gcc python3; do
    command -v $tool >/dev/null 2>&1 && echo "Tool    : $tool ok" || echo "Tool    : $tool MISSING"
done

echo
if [ $ok -eq 1 ]; then
    echo "RESULT: the Uniwill WMI interfaces are present. This machine is a candidate."
    echo "        (It is not a guarantee: the keyboard must also report RGB support to the EC.)"
    exit 0
fi
echo "RESULT: Uniwill WMI interfaces NOT all present. This project is unlikely to work here."
exit 1
