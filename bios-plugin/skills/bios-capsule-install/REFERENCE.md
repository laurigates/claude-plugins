# BIOS Capsule Install — tested machines

One row per machine this route was tried on. Add the outcome after the reboot.

| Machine (DMI) | Firmware | Capsule | fwupd | Result |
|---|---|---|---|---|
| Huawei MateBook X Pro 2020 (`MACHC-WAX9`) | Insyde, BIOS 1.07, ESRT 65543 | `UEFI_FW.bin` from Huawei HOTA package `OTA-MachC-BIOS-1.26`, ESRT class `5f84a7ba-5544-4ddf-9622-1704daa3f7a9`, target 65562 | 1.9.32 | `fwupdtool get-details` attached the cab to System Firmware, 65543 → 65562. Installer refused correctly with the charger unplugged, leaving `fwupd.conf` unchanged. **Flash pending** (2026-11-16) |
| Huawei MateBook X Pro 2018/2019 (`MACH-WX9`) | Insyde, BIOS 1.33 | `UEFI_FW.bin` from Huawei's Windows package | 2021-era | Flashed successfully per [derjohn's gist](https://gist.github.com/derjohn/2c19554415cea09830225314c2072807); commenters report the 2022 X Pro and MateBook 14 2022 too. Not reproduced here |

## Notes from the MateBook X Pro 2020 run

- `UEFI_FW.bin` is a signed PE (sections `.text`, `UEFI_FW`, `.xdata`,
  `.reloc`, `CERTIFICATE`), the same layout as the MACH-WX9 image that flashed
  for derjohn. fwupd passes the file to the firmware as-is.
- `/etc/fwupd/fwupd.conf` shipped with `OnlyTrusted=true` and
  `[uefi_capsule] DisableCapsuleUpdateOnDisk=true`.
- `fwupdmgr get-devices` listed System Firmware as `Updatable` with the single
  problem `Device requires AC power to be connected` while on battery.
- The RTC alarm (`rtcwake -m off`) did not wake this machine from S5, which
  matters only for unattended test loops, not for the update.
