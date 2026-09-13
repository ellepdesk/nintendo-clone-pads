#!/bin/sh
# Register the patched hid-nintendo with DKMS so it is rebuilt on every kernel
# update, install it for the running kernel, and switch to it now.
# Run with sudo from ~/nintendo-clone-pads/dkms
set -e
NAME=hid-nintendo-clonefix; VER=1.4; SRC=/usr/src/$NAME-$VER
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
# Unregister every version first (dkms needs the source tree to do that),
# then drop the old source trees; otherwise a dangling registration is left.
for v in $(ls /var/lib/dkms/$NAME/ 2>/dev/null | grep -vE "^kernel-"); do
    dkms remove "$NAME/$v" --all >/dev/null 2>&1 || rm -rf "/var/lib/dkms/$NAME/$v"
done
rm -rf /usr/src/$NAME-*
cp -r "$HERE/$NAME-$VER" "$SRC"
dkms add "$NAME/$VER"
dkms build "$NAME/$VER"
dkms install "$NAME/$VER"
# safety nets for Armbian-style in-place kernel upgrades (see the ensure script)
install -m 755 "$HERE/hid-nintendo-clonefix-ensure" /usr/local/sbin/hid-nintendo-clonefix-ensure
install -m 755 "$HERE/kernel-postinst-hook" /etc/kernel/postinst.d/zz-hid-nintendo-clonefix
install -m 644 "$HERE/hid-nintendo-clonefix-dkms.service" /etc/systemd/system/hid-nintendo-clonefix-dkms.service
systemctl daemon-reload
systemctl enable -q hid-nintendo-clonefix-dkms.service
# the old blacklist lines never matched the real module name; drop them
sed -i '/^blacklist nintendo_hid$/d;/^blacklist nintendo$/d' /etc/modprobe.d/blacklist.conf
depmod -a
echo; echo "module now resolved to: $(modinfo -n hid_nintendo)"
rmmod hid_nintendo 2>/dev/null || true
modprobe hid_nintendo
echo "loaded: $(cat /sys/module/hid_nintendo/initstate)"
dkms status
