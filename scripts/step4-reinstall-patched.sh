#!/bin/bash
# Step 4: install the security-patched libfprint + fprintd builds, restart, self-test.
set -euo pipefail
umask 022
ninja -C ${LIBFPRINT_SRC:-/home/${SUDO_USER:-$USER}/dev/libfprint}/build install >/dev/null
ninja -C ${FPRINTD_SRC:-/home/${SUDO_USER:-$USER}/dev/fprintd}/build install >/dev/null
ldconfig
# the polkit policy is dpkg-owned; keep the Debian copy
T=$(mktemp -d); (cd "$T" && apt-get download fprintd >/dev/null && dpkg-deb -x fprintd_*.deb x && cp x/usr/share/polkit-1/actions/net.reactivated.fprint.device.policy /usr/share/polkit-1/actions/); rm -rf "$T"
pkill -x fprintd || true; sleep 1
echo "--- installed build ids:"; sha256sum /usr/local/lib/libfprint-2.so.2.0.0 /usr/local/libexec/fprintd | cut -c1-16,65-
echo "--- self-test (fresh daemon, stored pairing):"
sudo -u "${SUDO_USER:?run via sudo}" timeout 60 /usr/local/bin/fprintd-list "$SUDO_USER"
echo "--- journal:"; journalctl -u fprintd -b --no-pager --since '1 min ago' | grep -vE 'Starting|Started' | tail -5
echo "STEP4 OK"
