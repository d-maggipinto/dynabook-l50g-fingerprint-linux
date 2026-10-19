# Fingerprint reader of the Dynabook Satellite Pro L50-G on Linux

Synaptics **06cb:00eb** ("Tudor" match-in-sensor family) working on Linux with a
fully open-source stack, plus a security review and fixes of that stack.

| | |
|---|---|
| Laptop | Dynabook Satellite Pro L50-G-13F (PBS12E) |
| Sensor | Synaptics 06cb:00eb, firmware 10.1 (build 3031663, 2019-08), product id 65 |
| Driver | `synatlsmoc` from [vojtapl/libfprint](https://github.com/vojtapl/libfprint) (LGPL-2.1, no vendor code) |
| Daemon | fprintd 1.94.5 + persistent-data patch from [vojtapl/synaTudorMiS](https://github.com/vojtapl/synaTudorMiS) |
| Tested | Kali rolling, kernel 7.1.5, GNOME/GDM Wayland: enrol, verify, lock screen, GDM login, reboot |

The IR "Face Authentication" camera of the same laptop (Chicony 04f2:b6cc,
`/dev/video2`, 640x360 greyscale) is a plain UVC device and needs no driver
work; face unlock was deliberately not set up (see the security notes).

## Why the obvious route fails

libfprint's in-tree `synaptics` driver speaks the BMKT protocol of Synaptics
"MIS" sensors. This sensor has the same USB endpoint layout and answers the raw
firmware version query, but the first BMKT command gets status `0x0401` and the
driver reports "unsupported firmware version". Adding the id there is useless;
the sensor needs the TLS-paired Tudor protocol, which the open `synatlsmoc`
driver implements.

## What was needed

1. One line in `synatlsmoc`'s id table (+ hwdb): `patches/0001`, upstream
   [vojtapl/libfprint#6](https://github.com/vojtapl/libfprint/pull/6).
2. fprintd must persist the driver's pairing data, otherwise every daemon start
   re-pairs the sensor and all enrolments vanish: `patches/0003` (the
   synaTudorMiS patch with a 0600 file mode,
   [vojtapl/synaTudorMiS#10](https://github.com/vojtapl/synaTudorMiS/pull/10)).
   The same applies to libfprint's `examples/enroll`; test through fprintd only.
3. Security fixes to the driver found during review: `patches/0002`, upstream
   [vojtapl/libfprint#7](https://github.com/vojtapl/libfprint/pull/7). Not
   sensor-specific; apply them.

Community hub entry:
[linux-fingerprint-drivers/devices/06cb:00eb](https://github.com/jedbillyb/linux-fingerprint-drivers/tree/master/devices/06cb:00eb)
(pull request [#37](https://github.com/jedbillyb/linux-fingerprint-drivers/pull/37)).

## Install (Debian/Kali, `/usr/local`, distro packages untouched)

```sh
sudo apt install meson ninja-build libgusb-dev libgudev-1.0-dev libnss3-dev \
  libgirepository1.0-dev libpixman-1-dev libcairo2-dev valac libssl-dev \
  libpolkit-gobject-1-dev fprintd libpam-fprintd
mkdir -p ~/dev && cd ~/dev
git clone https://github.com/vojtapl/libfprint && cd libfprint && git am ../dynabook-l50g-fingerprint-linux/patches/000[12]-*.patch
meson setup build -Dprefix=/usr/local -Dlibdir=lib -Ddrivers=all -Ddoc=false -Dgtk-examples=false \
  -Dudev_rules=enabled -Dudev_rules_dir=/etc/udev/rules.d -Dudev_hwdb=enabled -Dudev_hwdb_dir=/etc/udev/hwdb.d && ninja -C build
cd ~/dev && git clone https://gitlab.freedesktop.org/libfprint/fprintd && cd fprintd && git checkout v1.94.5 && patch -p1 < ../dynabook-l50g-fingerprint-linux/patches/0003-*.patch
meson setup build -Dprefix=/usr/local -Dpam=false -Dman=false -Dsystemd_system_unit_dir=/usr/local/lib/systemd/system \
  -Ddbus_service_dir=/usr/local/share/dbus-1/system-services && ninja -C build
```

Then, from this repo (each script prints a self-check; `uninstall.sh` reverts):

```sh
sudo bash scripts/step1-install-libfprint.sh     # install libfprint + udev rules
sudo bash scripts/step2-install-fprintd.sh       # install fprintd + systemd drop-in pointing at /usr/local
fprintd-enroll -f right-index-finger "$USER" && fprintd-verify "$USER"
sudo bash scripts/step3-harden-system.sh         # sandbox drop-in, pam_faillock, permissions (self-tests, rolls back)
```

PAM: Debian's `/etc/pam.d/gdm-fingerprint` already carries `pam_fprintd.so` and
GDM enables fingerprint when fprintd reports enrolled fingers, so GDM login and
the GNOME lock screen work with no PAM edits. `sudo`/polkit stay password-only
unless you enable the `pam-auth-update` fprintd profile (not recommended).

## Security notes

See [SECURITY-REVIEW.md](SECURITY-REVIEW.md). Short version:

- Templates never leave the sensor; Linux stores only the pairing blob
  (root-only, 0600).
- Before the fixes, a device that stopped the TLS handshake early could run
  every later command, including identify, in plaintext (vojtapl/libfprint#7).
- fprintd runs with no capabilities, native syscalls only, no namespaces or
  network (`scripts/fprintd-20-hardening.conf`, `systemd-analyze security` 1.5).
- Fingerprint attempts at GDM/lock screen are rate-limited with pam_faillock.
- Residual: someone who can boot another OS on the machine can pair with the
  sensor and read its template database, so keep a BIOS password, a locked boot
  order and full-disk encryption. A USBGuard allow-list for the sensor's
  internal port blocks plugged-in look-alike devices.
- Face unlock (Howdy) was rejected: it adds a root-running recogniser with no
  liveness guarantee as an "any-of" factor.

## License

Patches are derived from libfprint/fprintd and are LGPL-2.1. Scripts and
documentation in this repository are LGPL-2.1 as well.
