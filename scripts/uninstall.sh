#!/bin/bash
# Revert everything step1/step2 installed. Distro packages (libfprint-2-2, fprintd, libpam-fprintd) are untouched.
set -uo pipefail
umask 022
HERE=$(dirname "$(readlink -f "$0")")
rm -f /etc/systemd/system/fprintd.service.d/10-usr-local.conf; rmdir /etc/systemd/system/fprintd.service.d 2>/dev/null
grep -v "^/usr/share/" "$HERE/fprintd-files.txt" > "$HERE/.fprintd-rm.txt"
for list in "$HERE/.fprintd-rm.txt" "$HERE/libfprint-files.txt"; do while read -r f; do rm -f "$f"; done < "$list"; done
rm -rf /usr/local/include/libfprint-2 /usr/local/share/installed-tests/libfprint-2 /usr/local/libexec/installed-tests/libfprint-2
ldconfig; systemctl daemon-reload; udevadm control --reload; pkill -x fprintd || true
echo "reverted; ldconfig now:"; ldconfig -p | grep libfprint-2
