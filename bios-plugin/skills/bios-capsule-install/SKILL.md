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

> **Status as of this skill's creation:** the steps up to and including
> scheduling the update (`fwupdtool get-details`, the pre-flight checks, and
> the installer's refusal paths) were exercised on a MateBook X Pro 2020. The
> flash itself had not yet been performed on that model. Treat the reboot step
> as unverified until a result is recorded in [REFERENCE.md](REFERENCE.md).

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
`OnlyTrusted` setting, charger and battery, and ESP free space. Some reads need
root; it tries `sudo -n` and reports what it could not read.

| Result | Meaning |
|---|---|
| `no_esrt` | The firmware offers no capsule interface; this route is closed |
| `not_updatable` | fwupd will not update the device; read its `Problems` |
| `FWUPD_PROBLEMS=Device requires AC power…` | Only the charger is missing; plug it in before installing |
| `secure_boot_on` | fwupd's EFI helper must be the signed build |

## Step 2: Work out the target version number

fwupd compares the cabinet's release version with the ESRT `fw_version`
integer, so the cab must carry the integer the firmware will report after the
update. Read the current one from the preflight (`ESRT_FW_VERSION`,
`ESRT_VERSION_HEX`).

On the Insyde firmware this was tested on, BIOS `x.yy` is stored as
`(x << 16) | yy`: 1.07 reads 65543 (`0x00010007`), so 1.26 is 65562
(`0x0001001A`). That encoding is an observation on one vendor's firmware, not
a standard. Check that the current BIOS version decodes the same way
(`ESRT_VERSION_AS_MAJOR_MINOR` against `BIOS_VERSION`) before relying on it.

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

What it does, in order: refuses unless the DMI model matches, the charger is
connected, the battery is at or above the minimum, the cab checksum matches,
and the current ESRT version is below the target; asks the user to type
`flash`; turns fwupd's `OnlyTrusted` off, because a locally built cab is not
signed by the LVFS; runs `fwupdmgr install --no-reboot-check`; restores the
config file from a backup on exit; and tells the user to reboot. fwupd ≥ 1.9
reads `/etc/fwupd/fwupd.conf`; older releases read `daemon.conf`, which the
script falls back to.

Before handing it over, confirm with `AskUserQuestion` that the user accepts
the risk: a firmware update cannot be rolled back, and a failed flash can make
the machine unbootable. Remind them to keep the charger connected through the
reboot.

## Step 5: Verify after the reboot

```bash
fwupdmgr get-history
cat /sys/class/dmi/id/bios_version
bash "${CLAUDE_SKILL_DIR}/scripts/capsule-preflight.sh"
```

Success is `bios_version` showing the new version, the ESRT `fw_version`
equal to the target integer, and `last_attempt_status` 0. If the BIOS version
changed but fwupd records a failure, the target integer in the cab did not
match what the firmware reports; the flash itself still happened. Record the
outcome in [REFERENCE.md](REFERENCE.md).
