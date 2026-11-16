---
name: bios-update-diff
description: "Find what a BIOS update changed (microcode, EC, ACPI, ME) from boot logs and the new image. Use when a BIOS changelog says nothing useful."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/boot-firmware-diff.sh *), Bash(sudo bash ${CLAUDE_SKILL_DIR}/scripts/boot-firmware-diff.sh *), Bash(python3 -I ${CLAUDE_SKILL_DIR}/scripts/find-microcode.py *), Bash(journalctl --list-boots *), Bash(strings *), Bash(sha256sum *), Read, Grep, Glob
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# BIOS Update Diff

Vendor changelogs often say only "improves system stability". A direct diff of
the old and new images is best, but after a flash the old image is usually
gone. Vendors rarely keep old versions downloadable, and a capsule flash keeps
no backup. Three sources still show what changed:

1. the kernel log of a boot before and a boot after the update;
2. the new image itself;
3. versions the OS can read now and recorded before.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A BIOS update's changelog is uninformative | Getting the update file: `bios-plugin:bios-firmware-fetch` |
| Checking whether an update touched the EC, microcode or ACPI | Reverse-engineering the EC change itself: `bios-plugin:ec-firmware-analysis` |
| Before deciding to keep or roll back (rollback is usually impossible) | Installing it: `bios-plugin:bios-capsule-install` |

## Step 1: Compare a boot before and after

```bash
journalctl --list-boots          # pick the last boot on the old BIOS and the first on the new
sudo bash "${CLAUDE_SKILL_DIR}/scripts/boot-firmware-diff.sh" -2 -1
```

It diffs, per boot:

- the DMI/BIOS line;
- the microcode revision the BIOS loaded (`microcode: Updated early from: 0x…`);
- every ACPI table with its size and OEM ids;
- `[Firmware Bug]` and ACPI error lines, with addresses masked.

A table whose size changed was modified. The same lines on both boots mean
the update did not touch it. Run it on two boots under the same BIOS first as
a control; it should print `no differences`.

The journal must reach back to a boot on the old BIOS. Check
`journalctl --list-boots` and the retention settings in `journald.conf`
before flashing if you want this comparison later.

## Step 2: Read the new image

From the vendor package (see `bios-plugin:bios-firmware-fetch` for extracting
the capsule):

- **Regions it rewrites:** Insyde capsules carry a `$_IFLASH_INI_IMG` section
  (`platform.ini`) whose `[Region]` block says which regions the flash
  rewrites, e.g. `ME=0, EC=1`. `$_IFLASH_BIOSIMG` marks the BIOS region data.
- **Module list:** `UEFIExtract <region> all`; keep its report for a later
  comparison.
- **Embedded microcode:**
  `python3 -I "${CLAUDE_SKILL_DIR}/scripts/find-microcode.py" bios_region.bin --cpuid 0x806EC`
  lists CPUID, revision and date per update. The OS may load newer microcode
  itself (`intel-microcode`), so the runtime revision can be unchanged even
  when the BIOS's copy changed.
- **EC image and version:** `bios-plugin:ec-firmware-analysis`.
- **ACPI tables:** dump the live tables (`acpidump -b`, `iasl -d`) and keep
  them. Without an old dump you can describe the new tables but not diff them.

## Step 3: Compare versions the OS reports

| Version | Where |
|---|---|
| BIOS, EC | `/sys/class/dmi/id/bios_version`, `ec_firmware_release`, or `dmidecode -t 0` |
| System firmware (ESRT) | `/sys/firmware/efi/esrt/entries/*/fw_version` |
| Intel ME/CSME | `/sys/class/mei/mei0/fw_ver` |
| Battery model string | `/sys/class/power_supply/BAT0/model_name`. It can change with an EC update, which renames upower's history files |
| Wake devices | `/proc/acpi/wakeup` |
| Setup option defaults | the setup form (`bios-plugin:bios-setup-variables`) |

## Step 4: Look for the old image anyway

The vendor's update service may still hold older versions, and so may its
storage bucket. Try only vendor-hosted sources (`bios-plugin:bios-firmware-fetch`)
and time-box it. Community repositories (hackintosh/OpenCore projects) often
carry ACPI dumps of older versions. They are useful for read-only comparison,
but are not a trustworthy source of a flashable image.

## Worked example (Huawei MateBook X Pro 2020, BIOS 1.07 → 1.26)

| Item | 1.07 | 1.26 |
|---|---|---|
| BIOS-loaded microcode for 06-8e-0c | 0xC6 | 0xDE (2020-05-18) |
| EC firmware | 1.7 | 1.26 (`platform.ini`: `EC=1`, `ME=0`) |
| DSDT / one SSDT / another SSDT size | 0x43931 / 0x27A6 / 0x8458 | 0x439BF / 0x33B2 / 0x86A7 |
| Intel ME, wake devices, ACPI errors | | unchanged |
| Battery model string | `HB4593R1ECW-22T` | `HB4593R1ECW-22T0` |

The changelog said only "1. Improves system stability". No 1.07 image could
be found from vendor sources.
