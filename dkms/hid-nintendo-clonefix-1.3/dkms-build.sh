#!/bin/sh
# Build hid-nintendo against the kernel tree given as $1.
#
# Armbian kernels are built with a newer gcc than Ubuntu's default one. On
# arm64 the kernel's ftrace requires -fmin-function-alignment (gcc >= 14);
# building with an older gcc and simply dropping that flag produces a module
# that can BUG the kernel at load ("Misaligned patch-site"). So:
#  1. prefer a gcc whose major version matches the one the kernel was built with
#  2. otherwise build with the default gcc, dropping the alignment flag AND the
#     ftrace patch sites, which removes the alignment requirement.
set -e
KDIR="$1"
# auto.conf holds the compiler the kernel was really built with (Armbian's
# shipped .config may have been rewritten by the host gcc); values may be quoted
VTXT=$(sed -n 's/^CONFIG_CC_VERSION_TEXT=//p' "$KDIR/include/config/auto.conf" "$KDIR/.config" 2>/dev/null | head -1 | tr -d '"')
MAJ=$(printf '%s\n' "$VTXT" | sed -n 's/.*[^0-9.]\([0-9][0-9]*\)\.[0-9][0-9]*\.[0-9][0-9]*$/\1/p')
HOSTMAJ=$(gcc -dumpversion 2>/dev/null | cut -d. -f1)
echo "dkms-build.sh: kernel built with '${VTXT:-unknown}' (major ${MAJ:-?}); host gcc major ${HOSTMAJ:-?}"
if [ -n "$MAJ" ] && [ "$MAJ" = "$HOSTMAJ" ]; then
	exec make -C "$KDIR" M="$(pwd)" modules
elif [ -n "$MAJ" ] && command -v "gcc-$MAJ" >/dev/null 2>&1; then
	echo "dkms-build.sh: using gcc-$MAJ"
	exec make -C "$KDIR" M="$(pwd)" modules CC="gcc-$MAJ"
else
	echo "dkms-build.sh: no matching gcc; building without ftrace patch sites (install gcc-${MAJ:-14} for a normal build)"
	exec make -C "$KDIR" M="$(pwd)" modules CONFIG_CC_HAS_MIN_FUNCTION_ALIGNMENT= NO_FTRACE=1
fi
