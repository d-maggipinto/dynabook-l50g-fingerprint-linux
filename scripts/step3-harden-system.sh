#!/bin/bash
# Step 3: system-level hardening of the fingerprint stack. Self-tests fprintd and rolls back on failure.
set -uo pipefail
umask 022
HERE=$(dirname "$(readlink -f "$0")")
BK=/root/fprint-harden-backup-$(date +%Y%m%d-%H%M); mkdir -p "$BK"
DROPIN=/etc/systemd/system/fprintd.service.d/20-hardening.conf

echo "### 1. USB node: drop the temporary world-writable mode (back to udev default 0664 root:root)"
for d in /sys/bus/usb/devices/*; do [ "$(cat $d/idProduct 2>/dev/null)" = "00eb" ] && udevadm trigger --action=add "$d"; done
sleep 1; /bin/ls -l /dev/bus/usb/001/* | grep -v 'rw-rw-r--' || echo "all usb nodes are 0664"

echo "### 2. Restore the dpkg-owned polkit policy (local build only differed in translations)"
cp -a /usr/share/polkit-1/actions/net.reactivated.fprint.device.policy "$BK/"
T=$(mktemp -d); (cd "$T" && apt-get download fprintd >/dev/null && dpkg-deb -x fprintd_*.deb x && cp x/usr/share/polkit-1/actions/net.reactivated.fprint.device.policy /usr/share/polkit-1/actions/); rm -rf "$T"
dpkg -V fprintd && echo "dpkg -V fprintd: clean"

echo "### 3. Pairing-data storage permissions"
chmod 700 /var/lib/fprint /var/lib/fprint/0-persistent /var/lib/fprint/0-persistent/synatlsmoc 2>/dev/null
chmod 600 /var/lib/fprint/0-persistent/synatlsmoc/* 2>/dev/null
/bin/ls -laR /var/lib/fprint | grep -v '^total'

echo "### 4. Rate-limit fingerprint attempts at GDM/lock screen (pam_faillock, fingerprint path only)"
cp -a /etc/pam.d/gdm-fingerprint "$BK/"
if ! grep -q pam_faillock /etc/pam.d/gdm-fingerprint; then
  # pam_fprintd returns authinfo_unavail on prompt timeout / daemon restart (GDM keeps a prompt open at the lock
  # screen), so only auth_err/maxtries (real mismatches) may reach pam_faillock authfail.
  sed -i 's|^auth\trequired\tpam_fprintd.so$|auth\trequired\tpam_faillock.so preauth silent\nauth\t[success=2 authinfo_unavail=1 default=bad]\tpam_fprintd.so max-tries=3 timeout=30\nauth\t[default=die]\tpam_faillock.so authfail\nauth\t[default=die]\tpam_deny.so|' /etc/pam.d/gdm-fingerprint
  sed -i 's|^@include common-account$|account\trequired\tpam_faillock.so\n@include common-account|' /etc/pam.d/gdm-fingerprint
fi
grep -nE 'faillock|fprintd' /etc/pam.d/gdm-fingerprint

echo "### 5. Tighten the fprintd sandbox (drop-in), then self-test"
cp -a "$DROPIN" "$BK/" 2>/dev/null
cat > "$DROPIN" <<'EOT'
# Extra sandboxing for fprintd (synatlsmoc). Remove this file to revert.
[Service]
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=~@privileged @resources @obsolete @mount @cpu-emulation @debug @keyring
RestrictNamespaces=yes
RestrictSUIDSGID=yes
LockPersonality=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
PrivateUsers=no
IPAddressDeny=any
UMask=0077
DeviceAllow=
DeviceAllow=char-usb_device rw
ReadWritePaths=
ReadWritePaths=/sys/devices
EOT
systemctl daemon-reload; pkill -x fprintd; sleep 1
if sudo -u "${SUDO_USER:?run via sudo}" timeout 60 /usr/local/bin/fprintd-list "$SUDO_USER" 2>&1 | tee /dev/stderr | grep -q 'right-index-finger'; then
  echo "SELF-TEST OK: fprintd lists the enrolled finger under the tightened sandbox"
else
  echo "SELF-TEST FAILED: reverting sandbox drop-in"; rm -f "$DROPIN"; systemctl daemon-reload; pkill -x fprintd
  journalctl -u fprintd -b --no-pager --since '2 min ago' | tail -20
fi
systemd-analyze security fprintd.service --no-pager 2>/dev/null | grep -E 'Overall'
echo "backup in $BK"; echo "STEP3 DONE"
