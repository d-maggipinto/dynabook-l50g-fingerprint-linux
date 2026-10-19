# Security review — fingerprint stack on d4rkc0r3 (2026-10-19)

Scope: synatlsmoc driver (vojtapl/libfprint fork, branch synatlsmoc-00eb), fprintd 1.94.5 + persistent-data patch,
install layout in /usr/local, systemd sandbox, udev, PAM, pairing-data storage. Code review by a dedicated
reviewer agent (every driver file + libfprint core helpers + fprintd patch), system review by hand.

## Fixed in code (libfprint commit 423e1b1, fprintd commit 9e03367)
| Sev | Finding | Fix |
|---|---|---|
| High | TLS handshake completion was never checked: a device that stops the handshake early could drive every later command (incl. identify) in plaintext, making the sensor-certificate check moot | `tls_session_is_established()` gate on app-data receive, wrap/unwrap, and in the open SSM; ChangeCipherSpec accepted only after ServerHelloDone with derived keys |
| High | Use-after-free in `write_dft` (g_autoptr on a transfer whose ownership passes to `fpi_usb_transfer_submit`), reachable pre-TLS via the bootloader path | ownership fixed |
| Low | Pairing data saved before the sensor certificate was verified → a fake device at first pairing could poison the blob (persistent DoS) | `OPEN_SAVE_PAIRING_DATA` moved after verification + handshake, saved only when freshly paired |
| Low | Unbounded loops drivable by a malicious device (event-read, force-TLS-close) | bounded (64 / 2) |
| Low | Blob with host private key written with umask-derived mode | `g_file_set_contents_full(..., 0600)`; unit `UMask=0077` |
| Info | `memcmp` on Finished verify_data; unchecked `RAND_bytes`; test-only sample key header always included; string leak in persistent-data load; warning on first start | all fixed |

## Fixed at system level (step3-harden-system.sh, backup in /root/fprint-harden-backup-<date>)
- USB node back to udev default 0664 root:root (was left 0666 from testing).
- /var/lib/fprint tree 0700/0600; blob root-only.
- fprintd sandbox drop-in `20-hardening.conf`: no capabilities, native syscalls only, ~@privileged/@resources/…, RestrictNamespaces, ProtectProc=invisible, IPAddressDeny, UMask=0077, DeviceAllow limited to usb. `systemd-analyze security` exposure 1.5.
- PAM: `gdm-fingerprint` rate-limited with pam_faillock (3 fails → 10 min lockout of the fingerprint path only; password unaffected). pam_fprintd max-tries=3 timeout=30. No fprintd in sudo/polkit/common-auth.
- dpkg-owned polkit policy restored (local build differed only in translations); `dpkg -V fprintd` clean.

## Verified after patching
fprintd-list + fprintd-verify → verify-match with a fresh daemon reusing the stored pairing; no seccomp/permission denials in journal.

## Residual risks / not fixed here
- Physical attacker who can boot another OS could pair with the sensor and read its template DB (identifiers needed for a bypass). Mitigation = BIOS admin password + locked boot order + Secure Boot (hardening Phase 2 step 7) + LUKS (present).
- Plugged-in fake sensor with the same VID:PID is now limited to DoS (handshake gate). USBGuard allow-list for 06cb:00eb on its internal port would remove even that (hardening Phase 3).
- Protocol constant: the host-certificate signing key is public, so the sensor trusts any pairing host (vendor design; cannot fix in driver).
- Unknown TLS handshake message types are ignored rather than rejected (harmless with the established gate).
- Biometric FAR of the sensor itself is a vendor property; pam_faillock limits attempts.
- AIDE: run `aide --update` after the install so the new /usr/local files are baselined (hardening Phase 3 AIDE tuning).
- Monitor journal for "TLS handshake did not complete" / "Failed to save persistent data".

## Revert
`sudo bash ~/dev/synaptics-00eb/uninstall.sh` + remove `/etc/systemd/system/fprintd.service.d/20-hardening.conf` + restore `/etc/pam.d/gdm-fingerprint` from the backup dir.
