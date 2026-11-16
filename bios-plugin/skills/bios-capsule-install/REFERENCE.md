# BIOS Capsule Install — tested machines

One row per machine this route was tried on. Add the outcome after the reboot.

| Machine (DMI) | Firmware | Capsule | fwupd | Result |
|---|---|---|---|---|
| Huawei MateBook X Pro 2020 (`MACHC-WAX9`) | Insyde. Before: BIOS 1.07, ESRT 65543. After: BIOS 1.26 (dated 03/09/2023), EC 1.26, ESRT 65574 | `UEFI_FW.bin` from Huawei HOTA package `OTA-MachC-BIOS-1.26`, ESRT class `5f84a7ba-5544-4ddf-9622-1704daa3f7a9` | 1.9.32, `uefi_capsule` | **Flash verified 2026-11-16.** Secure Boot off, systemd-boot. ESRT `last_attempt_status` 0. The update wiped the NVRAM boot entries (see notes) |
| Huawei MateBook X Pro 2018/2019 (`MACH-WX9`) | Insyde, BIOS 1.33 | `UEFI_FW.bin` from Huawei's Windows package | 2021-era | Flashed successfully per [derjohn's gist](https://gist.github.com/derjohn/2c19554415cea09830225314c2072807); commenters report the 2022 X Pro and MateBook 14 2022 too. Not reproduced here |

## Notes from the MateBook X Pro 2020 run

- **Version encoding.** The ESRT stores BIOS x.yy with the decimal digits as
  hex digits: 1.07 → `0x00010007` (65543), 1.26 → `0x00010026` (65574). The cab
  used for this flash carried 65562, from an earlier, wrong assumption of
  `(x << 16) | yy` in decimal, which 1.07 happened to fit. The firmware flashed
  its own image regardless and now reports 65574; fwupd compares that against
  the cab's metainfo version, which is why the target matters for fwupd's
  record but not for the flash.
- **Boot entries wiped.** After the update `BootOrder` held only `0000`, a
  generic "EFI Hard Drive" entry. The Pop!_OS entry
  (`\EFI\systemd\systemd-bootx64.efi`) and fwupd's "Linux Firmware Updater"
  entry were gone. The machine still booted through the removable-media
  fallback `\EFI\BOOT\BOOTX64.EFI`. The OS entry was recreated with
  `sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L "<name>" -l '\EFI\systemd\systemd-bootx64.efi'`.
- **fwupd reports failure.** With its boot entry gone, fwupd recorded the update
  as "Failed: boot entry missing: no 'Linux Firmware Updater' entry found".
  `fwupdmgr clear-results <device-id>` failed with "failed to clear_result using
  uefi_capsule: unspecified error". The ESRT and DMI values in the
  tested-machines table are the evidence of success.
- `UEFI_FW.bin` is a signed PE (sections `.text`, `UEFI_FW`, `.xdata`,
  `.reloc`, `CERTIFICATE`), the same layout as the MACH-WX9 image that flashed
  for derjohn. fwupd passes the file to the firmware as-is.
- `/etc/fwupd/fwupd.conf` is mode 0640 root and shipped with
  `OnlyTrusted=true` and `[uefi_capsule] DisableCapsuleUpdateOnDisk=true`.
- `fwupdmgr get-devices` listed System Firmware as `Updatable` with the single
  problem `Device requires AC power to be connected` while on battery.
- The RTC alarm (`rtcwake -m off`) did not wake this machine from S5, which
  matters only for unattended test loops, not for the update.
