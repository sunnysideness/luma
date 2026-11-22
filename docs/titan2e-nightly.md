# Titan 2 Elite on the generic ARM nightly — bring-up notes

Status: bring-up report for **Luma 1.0.0-nightly.20261119.2** (commit
`690b346b5acbef886770b06e2489e42bb00f9197691237556288bf29e293d323`) on the
Unihertz Titan 2 Elite (MediaTek MT6878), booting from the microSD card while
Android stays on internal storage / slot b.

The phone boots to the Luma desktop, the account setup completes, display,
touch, keyboard, USB Ethernet and root SSH work. Wi-Fi/BT, audio, modem and GPU
acceleration are still open.

This branch still carries the **alpha model** (a hardware-targeted image built
from this branch). The notes below are what it takes to run the **new model**
(one generic ARM image + device kit) on this phone with the current nightly
userland, and they are the reason `config/mobile/titan2e-nightly/` exists.

## Pieces

| piece | where |
| --- | --- |
| OS | generic ARM nightly `luma/1/aarch64/nightly`, deployed on the SD card |
| device files | the alpha device payload (kernel modules, platform units, firmware, lpac) injected into the deployment |
| kernel | SimplyLuma/linux `e35761add` (the alpha boot-image source) + the microSD rail fix, boot_a only |
| boot | built-in DTB + built-in initramfs, Android boot v4 image + AVB hash footer (AOSP test key) |

The card is a 12 GiB GPT/ext4 `LumaRoot`, grown to the card on first boot; the
kernel mounts it from `/dev/mmcblk0p1` and boots the newest `/boot/loader/entries`
entry through `ostree-prepare-root`.

## Fixes needed for the generic nightly userland

All of these are in `config/mobile/titan2e-nightly/`:

### 1. `/var` is never mounted

`ostree-system-generator` exits 1 on this image (reproduced on every boot), so
no `var.mount` unit is generated and `/var` stays the deployment's own
directory. `/root` (a symlink to `var/roothome`), home directories, journals
and all state are then written into the deployment's shadow `var/` — and
disappear when something later runs `daemon-reload` and the real `/var` is
mounted over them. `etc/var.mount` is a static copy of the generated unit
(`What=/sysroot/ostree/deploy/luma/var`, `bind,slave,shared`) and is wanted by
`local-fs.target`.

Trace from the first boot (journal recovered from the shadow var):

```
luma (generato[164]: /usr/lib/systemd/system-generators/ostree-system-generator failed with exit status 1.
```

After installing the unit: `findmnt /var` →
`/dev/mmcblk0p1[/ostree/deploy/luma/var]`, `systemctl is-active var.mount` →
`active`, and `/root/.ssh` from the card is visible.

### 2. greenboot restarts the phone on a failed health check

greenboot 0.16 restarts the computer whenever a **required** check fails. The
alpha Titan healthcheck requires greetd + phoc + phosh; the generic nightly
runs gdm + Luma's GNOME shell, so the check failed on every boot and greenboot
reset the phone about three minutes in (abrupt reset: the journal has no
shutdown messages).

`healthcheck.sh` + `etc/greenboot-healthcheck-60-titan2e-nightly.conf` replace
the alpha check: it runs the OS's own required checks for the log and never
fails the unit, so the boot is blessed and slot a marked successful instead of
rolled back. On a healthy boot the log is:

```
titan2e-health: ok: 10-luma-display-manager.sh
titan2e-health: ok: 20-luma-shell-responsive.sh
titan2e-health: ok: 30-luma-network-manager.sh
titan2e-health: ok: 43-luma-updated.sh
titan2e-health: display manager active: gdm.service
```

### 3. systemd's hardware watchdog resets the SoC

The device payload sets `RuntimeWatchdogSec=20s` (`50-titan2e-watchdog.conf`)
on `mtk-wdt` (`Watchdog enabled (timeout=31 sec)`). On the grafted image PID 1
missed the feed and the phone reset. `etc/systemd-99-no-watchdog.conf` disables
it for bring-up; re-enabling it safely (find the stall, or raise the timeout
below 31 s) is open work.

### 4. Power key

`systemd-logind: Power key pressed short. Powering off...` — the default turned
a wake/check press into a clean poweroff. `etc/logind-10-luma-bringup.conf`
ignores power/suspend/lid.

### 5. Boot slot and boot counting

`luma-titan2e-boot-ok` writes the AOSP boot-control block in `misc` (slot a
successful, `0067 -> 0097`). `luma-titan2e-boot-bless` writes
`/boot/luma-boot-ok`; on this system it hangs on
`mount -o remount,rw /sysroot` because `/sysroot` is read-only in the booted
system — remount `/boot` instead (or write through the boot mount).

## The initramfs

`initramfs-init` is the Titan init used with the generic image. Compared with
`config/mobile/titan2e-initramfs/init` (alpha):

* creates its own `/proc /sys /dev /run /sysroot` mount points (the alpha
  initramfs relied on the initramfs root already having them; without them the
  kernel logs `Warning: unable to open an initial console` and init has no
  stdio);
* redirects everything to `/dev/kmsg` and logs every step, so progress is
  visible on the panel and recoverable from the journal;
* does not pre-create `/run/ostree` or `initramfs-mount-var`: ostree 2026.4
  treats an existing `/run/ostree` as fatal (`Failed to create /run/ostree:
  File exists`), and systemd's var.mount handles `/var`;
* writes `/boot/luma-diag.txt` and `/boot/prepare-root.log` before a restart,
  and never writes the boot-control block in `misc`.

## Kernel: microSD rail

Bootloader `g72_dfl_tee_13be6e3_202610280133` does not leave the card rail
powered. The board DT pins `mt6369_vmch` to a fixed 3.0 V, and the MMC OCR mask
always spans two 100 mV ranges, so `regulator_set_voltage()` fails and mtk-sd
returns before enabling the rail. The card needs 2.8 V on this unit (2.7 V
fails, 3.3/3.5 V give CRC errors; the PMIC reports HWCID `0x69` while
`mt6369-regulator.c` defines `0x0009`). Fix: DT range + explicit 2.8 V in
mtk-sd `set_ios()` (sent separately against SimplyLuma/linux
`titan2e/msdc1-pinctrl-drive`).

## Open issues

* Wi-Fi/BT: modules load, `hci0` exists, but `luma-titan2e-connsys-up` fails at
  `echo 1 >/dev/wmtWifi` (EIO) and no `wlan0` appears.
* Audio: ALSA card `Titan2Elite` exists; speaker amplifier firmware
  `frsm-spk1.bin` is copied to `/var/lib/titan2e-connsys/firmware` but the
  kernel looks in the firmware search path; wireplumber has no working mixer.
* Modem: CCCI modules load and `luma-modemd` starts, then the unit fails and
  ModemManager registration times out.
* GPU: `panthor` loads, but this image's Mesa has no Mali-G615 support, so the
  session renders with llvmpipe.
* Greenboot success plumbing: `bootloader-update.service` (UEFI updater) and
  `NetworkManager-wait-online` are not meaningful on this device.
* New-model migration: `devices/titan2elite` is still the alpha model. The
  generic-image path needs a place for an SD-card install (the phone-userdata
  kit flow assumes Android's userdata partition), a signed device repository,
  and the files in this directory wired into the build.

## Evidence

Boot and crash evidence used here: journal from the deployment's shadow var,
pstore (`console-ramoops-0`), and the kernel console on the phone. The bring-up
workspace with the full logs, the card/boot build scripts and the device-kit
port analysis is at `andres/LumaTitan` (private GitLab) for the maintainers on
request.
