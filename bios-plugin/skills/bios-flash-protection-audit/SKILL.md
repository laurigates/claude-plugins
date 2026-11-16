---
name: bios-flash-protection-audit
description: "Audit Intel PCH SPI flash protection and Boot Guard from Linux, read-only, and take a verified full flash backup. Use when planning a firmware patch or an external flash."
allowed-tools: Bash(sudo bash ${CLAUDE_SKILL_DIR}/scripts/spi-protect.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/build-flashrom.sh *), Bash(sha256sum *), Bash(cmp *), Read, Grep, Glob
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# BIOS Flash Protection Audit (Intel PCH, read-only)

Before changing anything in the SPI flash (patching an EC image, a BIOS
region, a setup default), find out three things from the running OS:

1. Can the OS write the region at all, or is an external programmer needed?
2. Does anything verify the image at boot (Intel Boot Guard)?
3. Is there a verified full backup to restore from?

Everything here only reads: PCI config space, the SPI controller's registers
and one MSR, then the flash contents.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Deciding whether a firmware patch can be written from Linux | Installing a vendor capsule: `bios-plugin:bios-capsule-install` |
| Taking a full SPI flash backup before risky work | Writing the flash externally: `bios-plugin:bios-external-programmer` |
| Checking whether Boot Guard would reject a modified image | Analysing the EC image inside the flash: `bios-plugin:ec-firmware-analysis` |

## Step 1: Read the protection registers

```bash
sudo bash "${CLAUDE_SKILL_DIR}/scripts/spi-protect.sh"
```

The script auto-detects the Intel SPI controller (vendor 8086, class 0c80);
pass `--dev BB:DD.F` to override. The register offsets are those of the 100–
to 400-series PCH. It was verified on Comet Lake LP; check the datasheet
before trusting it on another generation.

How to read the output:

| Field | Meaning |
|---|---|
| `BIOS_CNTL` `BIOSWE=0 BLE=1 SMM_BWP=1` | BIOS-region writes only from SMM; the OS cannot enable them |
| `HSFS` `FLOCKDN=1` | Protected ranges and region access are locked until the next reset |
| `PRn ... WP=1` | That flash range is write-protected for every master, regardless of region access |
| `FRAP` / `BIOS_master=rw` | What the host CPU may read/write per region (descriptor, BIOS, ME, …) |
| `FREGn` | The region map: where the BIOS and ME regions sit in the chip |
| `MSR_0x13A=0x0…0` | No Boot Guard ACM ran: nothing verifies the BIOS region at boot |

A target address inside any `WP=1` range, with `FLOCKDN=1`, cannot be written
from the OS. The only route is an external programmer on the chip. Reading is
possible when the range has `RP=0` and the region is readable (`r`).

`/dev/mem` access needs a kernel without `CONFIG_IO_STRICT_DEVMEM` (or booted
with `iomem=relaxed`) and no kernel lockdown. Check
`/sys/kernel/security/lockdown`.

## Step 2: Get a flashrom with the internal programmer

`flashrom -p internal` needs a version that knows the chipset. Ubuntu 22.04's
1.2 does not know Comet Lake; Homebrew's Linux build has no internal
programmer at all (it lists only USB/serial programmers). Build one:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/build-flashrom.sh"          # v1.4.0 by default
sudo ~/src/flashrom/build/flashrom -p internal --flash-name
```

flashrom prints a long warning about laptops and ECs sharing the flash. A
read through the PCH's hardware sequencing is the normal, low-risk case.
Never erase or write internally on a laptop: if the EC shares the chip, erase
bricks it.

## Step 3: Back up and verify

```bash
sudo ~/src/flashrom/build/flashrom -p internal -r spi-full-1.bin
sudo ~/src/flashrom/build/flashrom -p internal -r spi-full-2.bin
sha256sum spi-full-*.bin                    # must be identical
```

Keep a copy off the machine. Two identical reads make the backup
trustworthy, and an external read later can be compared against it. Expect
small differences in the UEFI variable store and ME data if the machine has
booted between the reads.

To locate a component inside the dump, search for its signature rather than
assuming the capsule's layout maps 1:1. The EC image's `PHCM` header is an
example: `python3 -c "import re;d=open('spi-full-1.bin','rb').read();print([hex(m.start()) for m in re.finditer(b'PHCM',d)])"`.

## Worked example (Huawei MateBook X Pro 2020, BIOS 1.26)

- 16 MB Macronix chip (JEDEC ID of the MX25L128xx family). Descriptor at 0x0,
  ME 0x1000–0x3FFFFF, BIOS 0x400000–0xFFFFFF.
- `BLE=1`, `SMM_BWP=1` and `FLOCKDN=1`. PR1 (0x480000–0x96FFFF) write-protects
  the EC image at 0x600000, so it can only be written externally.
- `FRAP` read mask 0xCF (descriptor, BIOS and ME readable).
- MSR 0x13A = 0: Boot Guard not active.
- Two flashrom 1.4.0 reads were byte-identical. The EC image in the dump
  matched the vendor capsule's EC image exactly at 0x600000.
