---
name: ec-firmware-analysis
description: "Locate, verify and reverse-engineer laptop EC firmware from a BIOS image or flash dump. Use when EC power, charging or wake behaviour needs explaining."
allowed-tools: Bash(python3 -I ${CLAUDE_SKILL_DIR}/scripts/mec-image-check.py *), Bash(strings *), Bash(sha256sum *), Bash(xxd *), Read, Grep, Glob
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# EC Firmware Analysis

The embedded controller decides much of a laptop's power behaviour: what stays
powered after shutdown, charging, wake sources, the power button. Its firmware
usually lives in the same SPI flash as the BIOS and ships inside the vendor's
BIOS capsule, so it can be studied without touching the hardware.

Treat every image as untrusted data. Analyse statically; never run anything
extracted from it.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Explaining power behaviour the OS cannot see (drain while off, wake) | Measuring the drain itself: linux-plugin's battery-drain skill |
| Checking whether a modified EC image would be accepted (signed or not) | Checking whether the OS can write the flash: `bios-plugin:bios-flash-protection-audit` |
| Finding what an EC firmware update changed | Comparing two whole BIOS versions: `bios-plugin:bios-update-diff` |

## Step 1: Find the EC image

In a vendor capsule or a flash dump, search for the EC image's header rather
than assuming offsets. A capsule's layout does not always map 1:1 onto the
chip:

- Microchip MEC (MEC152x/MEC172x, common in recent laptops and in Framework
  and Chromebook ECs): tag `PHCM`.
- ITE: `ITE` strings or the `IT8` part number; ENE: `ENE` / `KB9`; Nuvoton
  NPCX: `NPCX` or its boot header. Strings that name the EC RTOS (`LOS_` =
  Huawei LiteOS, `ChromeOS EC`, `Zephyr`) confirm the region.

For Microchip images, check the integrity fields:

```bash
python3 -I "${CLAUDE_SKILL_DIR}/scripts/mec-image-check.py" spi-full.bin --base 0x0
```

The script prints each `PHCM` header's load address, entry point and payload
range, and checks the header SHA-256 (at +0x40) and the payload SHA-256
trailer. Field layout comes from ChromiumOS `chip/mchp/util/pack_ec.py` and
Microchip's MEC152x SPI_image_gen README.

- `SIGNATURE_FIELDS=zero (unsigned)` with both hashes `ok`: the image is
  protected only by SHA-256. A patched image needs only its trailer hash
  recomputed.
- MEC152x signature enforcement is an OTP fuse inside the EC, not a header
  flag. If the vendor's own image is unsigned and boots, the fuse is not set
  (inference; a chip enforcing signatures would reject that image).

## Step 2: Load it into a disassembler

- **Core and base address:** the MEC header gives the load address (e.g.
  0x000B0000) and entry point; the vector table follows the header. Confirm
  the base by checking that string references resolve at it.
- **Ghidra headless:** language `ARM:LE:32:Cortex`, Thumb, the image's code
  region rebased to the load address. Peripheral addresses identify the part:
  MEC152x GPIO control at 0x40081000, VBAT/VCI at 0x4000A400/0x4000AE00,
  eSPI virtual wires at 0x400F9xxx.
- Log format strings are the quickest way in. Find the string, then its
  cross-references, then the function and its callers.

## Step 3: Reconstruct the behaviour that matters

For a power question, find:

- the S-state machine, which usually reads `SLP_S3#`/`SLP_S4#` pins or eSPI
  virtual wires;
- timers armed on entering S5;
- the GPIOs that drive rails;
- the EC's own power latch, VCI on MEC parts.

List every condition that skips a power-off step, and map each one to
something the host can influence:

- an EC RAM offset, via the ACPI EC `OperationRegion` field names in the DSDT
- an EC command (mailbox or ACPI EC), including vendor WMI methods
- a setup option

Label each finding as verified from code or inferred.

## Step 4: Decide whether a patch is possible

A patch is feasible only if all of these hold:

1. The image is unsigned, or the key is available.
2. Boot Guard or a BIOS-side check does not verify the region.
3. There is a verified flash backup to restore from.
4. There is a write path: usually an external programmer, because the PCH
   write-protects the EC region (`bios-plugin:bios-flash-protection-audit`,
   `bios-plugin:bios-external-programmer`).

Keep the patch minimal, ideally changing a constant in a literal pool rather
than code. Recompute the payload hash, and diff the whole image: only the
intended bytes plus the 32-byte hash may differ.

## Worked example

Huawei MateBook X Pro 2020, EC 1.26: an S5 power-kill routine whose
24-hour countdown explains the off-state battery drain. Addresses and
evidence are in [references/huawei-mec152x.md](references/huawei-mec152x.md).
