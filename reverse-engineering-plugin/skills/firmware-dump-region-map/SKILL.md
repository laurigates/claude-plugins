---
name: firmware-dump-region-map
description: Enumerate every region of a firmware/BIOS/SPI-flash dump before reverse-engineering one. Use when handed a flash image and about to carve out the EC, a DXE driver or the ME region. Covers the flash descriptor, extracting compressed UEFI volumes (raw grep misses strings), and host-vs-device split.
user-invocable: false
allowed-tools: Bash(uefi-firmware-parser *), Bash(binwalk *), Bash(ifdtool *), Bash(UEFIExtract *), Bash(grep *), Bash(rg *), Bash(python3 -I *), Read, Grep, Glob
created: 2026-11-17
modified: 2026-11-17
reviewed: 2026-11-17
---

# Firmware-Dump Region Map

A full SPI-flash dump is several binaries in a trench coat. Reverse-engineering
one component while ignoring the rest is the classic mistake: the piece that
answers your question is often in a region you never extracted.

> Incident: a fingerprint-key investigation carved the EC firmware out of a
> 16 MB `biosflash.bin` and reversed its Cortex-M code for days — while the
> **x86 UEFI DXE driver that drives the exact host-side protocol** sat
> unexamined in 17 compressed volumes of the same dump.

## Enumerate first

A typical Intel laptop SPI image has, per the **flash descriptor** at offset 0:
- **Descriptor** — region map + access perms.
- **ME/CSME region** — the Management Engine firmware (and its DAL applets).
- **EC region** — embedded-controller firmware (often a raw MCU image, e.g.
  Microchip MEC Cortex-M, not in a UEFI volume).
- **BIOS region** — the UEFI PEI/DXE/SMM volumes (the x86 host code).

Map them before carving one:

```sh
# Region/descriptor + ME layout:
UEFIExtract <dump>.bin            # or: ifdtool -d <dump>.bin   (coreboot)
# UEFI volume + module tree (extracts and DECOMPRESSES):
uefi-firmware-parser -e <dump>.bin -O <outdir>
# Quick triage of boundaries / embedded blobs:
binwalk <dump>.bin
```

## UEFI modules are LZMA-compressed — raw grep misses them

A `grep` for a string, a GUID, or a pointer across the raw image returns **zero**
for anything inside a compressed firmware volume, even when it's there. That's an
absence-looks-like-an-answer trap, not evidence the content is missing.

```sh
grep -c -a _FVH <dump>.bin        # N firmware volumes present (compressed)
# -> then EXTRACT, and search the decompressed modules:
rg -a 'MyAcpiDevice|FPKY' <outdir>
# a GUID is bytes, little-endian mixed-endian: search after extraction
python3 -c "import sys;d=open('<module>','rb').read();print(d.count(bytes.fromhex('<le-guid-hex>')))"
```

Only strings in uncompressed regions (often the EC/MCU image, or the descriptor)
show up on a raw grep. If a raw grep hits, note *which region* the offset falls
in before concluding anything.

## A feature has a host side and a device side — in different regions

The host-visible behaviour (ACPI methods, the DXE/SMM driver that fills a shared
window, the EC command sequence) lives in the **BIOS region**; the device-side
implementation lives in the **EC/ME region** or the peripheral's own MCU. When a
protocol is only half-clear from one side, the other half is in a different
region of the same dump. Reverse both before concluding a path is dead.

Related: driver-version archaeology — when a vendor ships multiple driver/
firmware versions, the one **contemporaneous with the hardware** (match build
dates) is the faithful reference; a newer version may have re-architected the
scheme. Diff versions; component lists that appear/disappear reveal the design
(e.g. an ME storage applet present only in the older package).

## Hand off to the right tool

- Carve a region → feed the x86/ARM binary to `ghidra-headless-decompile`.
- ACPI tables (SSDT/DSDT) extracted from the image → `acpi-table-re`.
- A TEE/SGX enclave or ME applet in the ME region → `sgx-sealed-secret-recovery`.

## Related

- `tools-plugin:binary-analysis` — `binwalk`/`strings`/entropy triage.
- `ghidra-headless-decompile`, `acpi-table-re`, `sgx-sealed-secret-recovery`.
