#!/bin/bash
# Step 2: install patched fprintd into /usr/local and point the systemd unit at it
set -euo pipefail
umask 022
SRC=${FPRINTD_SRC:-/home/${SUDO_USER:-$USER}/dev/fprintd}
ninja -C "$SRC/build" install
mkdir -p /etc/systemd/system/fprintd.service.d
cat > /etc/systemd/system/fprintd.service.d/10-usr-local.conf <<'EOT'
# Use the locally built fprintd (synatlsmoc persistent-data patch). Remove this file to revert.
[Service]
ExecStart=
ExecStart=/usr/local/libexec/fprintd
EOT
systemctl daemon-reload
pkill -x fprintd || true
echo "--- unit resolves to:"; systemctl show fprintd.service -p ExecStart -p FragmentPath -p DropInPaths
echo "--- binary links:"; ldd /usr/local/libexec/fprintd | grep fprint
echo "STEP2 OK"
