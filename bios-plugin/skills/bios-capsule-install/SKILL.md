---
name: bios-capsule-install
description: "Install a vendor UEFI capsule from Linux via fwupd. Use when a vendor is not on LVFS and its BIOS update ships only as a Windows package or bare capsule."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/capsule-preflight.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/build-capsule-cab.sh *), Bash(fwupdmgr get-devices *), Bash(fwupdmgr get-history *), Bash(fwupdtool get-details *), Bash(sudo fwupdtool get-details *), Bash(gcab -l *), Bash(sha256sum *), Read, Grep, Glob, AskUserQuestion
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# BIOS Capsule Install (Linux, fwupd)

fwupd can apply any UEFI capsule the firmware advertises through its ESRT
(EFI System Resource Table), not only packages from the LVFS. A vendor that
ships BIOS updates only as a Windows installer usually wraps a capsule image
inside it; packaged into a fwupd cabinet, it installs from Linux.

Prior art: [derjohn's gist](https://gist.github.com/derjohn/2c19554415cea09830225314c2072807)
for the Huawei MateBook X Pro 2018/2019, which this skill generalises.

> **Verified once, end to end:** a Huawei MateBook X Pro 2020 went from BIOS
> 1.07 to 1.26 through this route on 2026-11-16 (fwupd 1.9.32, Secure Boot
> off, systemd-boot). For any other model, treat the flash as unverified until
> a result is recorded in [REFERENCE.md](REFERENCE.md); the firmware there may
> encode versions differently or behave differently on reboot.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| You have a vendor capsule image and want to install it from Linux | The vendor is on the LVFS: `fwupdmgr update` |
| Checking whether a machine can take a capsule update at all | Finding the firmware file first: `bios-plugin:bios-firmware-fetch` |

## Step 1: Check the machine

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/capsule-preflight.sh" --min-battery 30
```

It reads, and changes nothing: DMI model and BIOS version, UEFI and Secure
Boot state, the ESRT system-firmware entry (class GUID, current and lowest
supported version), whether fwupd lists **System Firmware** as `Updatable`
and with which `Problems`, whether the packager and `gcab` exist, the
`OnlyTrusted` setting, charger and battery, ESP free space, the boot order,
and whether the removable-media fallback loader `\EFI\BOOT\BOOTX64.EFI`
exists. Some reads need root; it tries `sudo -n` and reports what it could not
read.

| Result | Meaning |
|---|---|
| `no_esrt` | The firmware offers no capsule interface; this route is closed |
| `not_updatable` | fwupd will not update the device; read its `Problems` |
| `FWUPD_PROBLEMS=Device requires AC power…` | Only the charger is missing; plug it in before installing |
| `secure_boot_on` | fwupd's EFI helper must be the signed build |
| `no_fallback_loader` | Do not flash: if the update wipes the boot entries, nothing boots the OS. Install a fallback loader first |

## Step 2: Work out the target version number

fwupd compares the cabinet's release version with the ESRT `fw_version`
integer, so the cab should carry the integer the firmware will report after
the update. Read the current one from the preflight (`ESRT_FW_VERSION`,
`ESRT_VERSION_HEX`).

On the Huawei Insyde firmware this was verified on, BIOS `x.yy` is stored with
the decimal digits written as hex digits: 1.07 reads 65543 (`0x00010007`) and
1.26 reads 65574 (`0x00010026`). Compute the target the same way:

```bash
printf '%d\n' $(( (0x1 << 16) | 0x26 ))   # BIOS 1.26 -> 65574
```

That encoding is an observation on one vendor's firmware, not a standard.
Before relying on it, check that the preflight's `ESRT_VERSION_AS_HEX_DIGITS`
equals `BIOS_VERSION` for the current version. A single sample cannot tell the
encodings apart when every digit is below ten (1.07 fits both `0x0007` and
decimal 7), so a version with an 8 or 9 in the minor, or a second sample, is
what confirms it.

A wrong target does not stop the flash: the firmware applies its own image and
reports its own version. It does make fwupd's post-reboot comparison fail.

## Step 3: Build the cabinet on the target machine

Needs fwupd's `/usr/share/fwupd/firmware_packager.py` (fwupd 1.9 names it
that, not `firmware-packager`) and `gcab`.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/build-capsule-cab.sh" \
  --bin UEFI_FW.bin --sha256 <image sha256> \
  --guid <ESRT_FW_CLASS> --version <target integer> \
  --name "<Model> BIOS" --vendor <Vendor> --out firmware.cab
sudo fwupdtool get-details firmware.cab
```

`get-details` must show the cab attached to the **System Firmware** device
with `New version` equal to the target. If it lists no matching device, the
GUID is wrong; stop.

## Step 4: Install, by the person at the machine

Hand over `scripts/install-capsule.sh` for the user to run in their own
terminal. It asks for confirmation and the sudo password, so it does not run
from an agent session:

```bash
./install-capsule.sh --cab firmware.cab --sha256 <cab sha256> --model <DMI product_name> \
  --guid <ESRT_FW_CLASS> --target-version <target integer> --min-battery 30
```

What it does, in order:

1. Refuses unless the DMI model matches, the charger is connected, the battery
   is at or above the minimum, the cab checksum matches, and the current ESRT
   version is below the target.
2. Refuses unless `\EFI\BOOT\BOOTX64.EFI` exists on the ESP, and saves
   `efibootmgr -v` to `~/efibootmgr-before-update-<timestamp>.txt`.
3. Asks the user to type `flash`.
4. Turns fwupd's `OnlyTrusted` off, because a locally built cab is not signed
   by the LVFS, then asserts the file holds exactly one `OnlyTrusted=false`
   and one `[fwupd]` section.
5. Runs `fwupdmgr install --no-reboot-check`, restores the config file from a
   backup on exit, and tells the user to reboot.

fwupd ≥ 1.9 reads `/etc/fwupd/fwupd.conf`; older releases read `daemon.conf`,
which the script falls back to. The file is usually mode 0640 root, so every
read goes through `sudo`. A plain `grep` fails silently there and sends a naive
script into its append branch, which writes a second `[fwupd]` section.

Before handing it over, confirm with `AskUserQuestion` that the user accepts
the risk: a firmware update cannot be rolled back, and a failed flash can make
the machine unbootable. Remind them to keep the charger connected through the
reboot.

## Step 5: Verify after the reboot

```bash
cat /sys/class/dmi/id/bios_version /sys/class/dmi/id/bios_date
bash "${CLAUDE_SKILL_DIR}/scripts/capsule-preflight.sh"
sudo efibootmgr -v
```

**Judge the result from the firmware, not from fwupd.** Success is
`bios_version` showing the new version, and the ESRT entry reporting
`fw_version` and `last_attempt_version` at the new value with
`last_attempt_status` 0.

fwupd's history can say "Failed" after a successful flash. On the verified
machine it reported `boot entry missing: no 'Linux Firmware Updater' entry
found`, because the firmware update had wiped the NVRAM boot entries,
including fwupd's own. `fwupdmgr clear-results <device-id>` then failed with
`failed to clear_result using uefi_capsule: unspecified error`, so the stale
"Failed" stays in the history. It is not evidence that the flash failed.

**Check the boot entries.** Compare `efibootmgr -v` with the file saved before
flashing. On the verified machine `BootOrder` came back as only the generic
"EFI Hard Drive" entry: the distribution's entry and fwupd's were gone, and the
machine booted only through the fallback `\EFI\BOOT\BOOTX64.EFI`. Recreate the
OS entry from the saved record, with the disk and partition of the ESP and the
loader path the old entry pointed at:

```bash
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L "<distribution name>" -l '\EFI\systemd\systemd-bootx64.efi'
```

Record the outcome in [REFERENCE.md](REFERENCE.md).
