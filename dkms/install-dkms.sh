#!/bin/sh
# Register the patched hid-nintendo with DKMS so it is rebuilt on every kernel
# update, install it for the running kernel, and switch to it now.
# Run with sudo from ~/nintendo-clone-pads/dkms
set -e
NAME=hid-nintendo-clonefix; VER=1.2; SRC=/usr/src/$NAME-$VER
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
rm -rf "$SRC"; cp -r "$HERE/$NAME-$VER" "$SRC"
dkms remove "$NAME/$VER" --all >/dev/null 2>&1 || true
dkms add "$NAME/$VER"
dkms build "$NAME/$VER"
dkms install "$NAME/$VER"
# the old blacklist lines never matched the real module name; drop them
sed -i '/^blacklist nintendo_hid$/d;/^blacklist nintendo$/d' /etc/modprobe.d/blacklist.conf
depmod -a
echo; echo "module now resolved to: $(modinfo -n hid_nintendo)"
rmmod hid_nintendo 2>/dev/null || true
modprobe hid_nintendo
echo "loaded: $(cat /sys/module/hid_nintendo/initstate)"
dkms status
