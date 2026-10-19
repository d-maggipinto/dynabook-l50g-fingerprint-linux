#!/bin/bash
# Step 1: build dep for fprintd + install the synatlsmoc-enabled libfprint fork into /usr/local
set -euo pipefail
umask 022
SRC=${LIBFPRINT_SRC:-/home/${SUDO_USER:-$USER}/dev/libfprint}
apt-get install -y libpolkit-gobject-1-dev
ninja -C "$SRC/build" install
ldconfig
udevadm control --reload
udevadm trigger --subsystem-match=usb --attr-match=idVendor=06cb
echo "--- installed:"; ls -l /usr/local/lib/libfprint-2.so* /etc/udev/rules.d/70-libfprint-2.rules /etc/udev/hwdb.d/60-autosuspend-libfprint-2.hwdb
echo "--- ldconfig resolves libfprint-2 to:"; ldconfig -p | grep libfprint-2
echo "STEP1 OK"
