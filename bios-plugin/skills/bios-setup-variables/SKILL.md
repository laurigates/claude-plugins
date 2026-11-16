---
name: bios-setup-variables
description: "Read or change hidden UEFI setup options from Linux via efivarfs, using offsets from the setup form (IFR). Use when a BIOS option is hidden from the setup menu."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/setup-var.sh * show), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/setup-var.sh * backup *), Bash(ls /sys/firmware/efi/efivars*), Bash(sha256sum *), Bash(cmp *), Read, Grep, Glob, AskUserQuestion
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# BIOS Setup Variables (hidden options via efivarfs)

Insyde, AMI and Phoenix firmware keep their setup options in ordinary UEFI
variables (`Setup`, `PchSetup`, `CpuSetup`, `SaSetup`, `MeSetupStorage`, …).
Most options the vendor hides from the menu are still defined in the setup
form (IFR) and still read at boot. Knowing the option's variable and byte
offset is enough to read it from Linux, and on many machines to change it.

> **Tested on one machine:** a Huawei MateBook X Pro 2020 (Insyde, BIOS 1.26),
> where `PchSetup` offset 0x4 ("DeepSx Power Policies") was changed 0 → 4 and
> the laptop booted normally with it. Firmware that locks its setup variables
> (variable policy, `VarCheck`) refuses the write; `noop` (Step 4) finds out
> without changing anything.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| An option exists in the setup form but not in the menu | The option is in the menu: change it there |
| Auditing the current value of hidden options | Building a full option list from the form: see Step 1 |
| Reverting a setup variable from a backup | The machine no longer boots: reset the firmware settings (CMOS/RTC battery or vendor key combo) |

## Step 1: Find the option in the setup form

Extract the setup forms from a firmware image (the vendor capsule, or a flash
backup from `bios-plugin:bios-flash-protection-audit`):

1. Find the setup driver (`SetupUtility`, `Setup`, `AdvancedSetup`) with
   `UEFIExtract <image> all` and search for the option's prompt string.
2. Run [IFRExtractor-RS](https://github.com/LongSoft/IFRExtractor-RS) on that
   module (`ifrextractor <module>.efi verbose`) to get a text dump.

In the dump, a question names its variable store by a local id; the varstore
lines map that id to the EFI variable's name, GUID and size:

```
VarStoreEfi Guid: 4570B7F1-ADE8-4943-8DC3-406472842384, VarStoreId: 0x5, ..., Size: 0x6EC, Name: "PchSetup"
OneOf Prompt: "DeepSx Power Policies", ..., VarStoreId: 0x5, VarOffset: 0x4, ..., Size: 8, Min: 0x0, Max: 0x4
  OneOfOption Option: "Disabled" Value: 0, Default, MfgDefault
  OneOfOption Option: "Enabled in S4-S5/Battery" Value: 3
  OneOfOption Option: "Enabled in S4-S5" Value: 4
```

- `VarStoreId` is local to its `FormSet`: map it with the varstore lines of
  the same formset.
- `VarOffset` is relative to the variable's data. `Size` is in **bits** for
  `OneOf`/`Numeric`.
- The varstore `Size` is the variable's data size. Pass it as `--data-size`,
  so a firmware update that changes the layout is caught before any write.
- An option inside `SuppressIf`/`GrayOutIf` is hidden or greyed out under that
  condition. Hiding it does not stop the firmware reading it.

A parser that turns a whole dump into one table with live values is being
written and is not part of this skill yet. Until then, work from the dump by
hand: `grep -n 'Prompt: "<option>"'` finds the question, and the nearest
preceding `VarStoreEfi` line with the same `VarStoreId` in that `FormSet`
names the variable.

## Step 2: Read the current value

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-var.sh" --var PchSetup-4570b7f1-ade8-4943-8dc3-406472842384 --offset 0x4 --data-size 0x6EC show
```

The efivarfs file is the variable's 4-byte attribute word followed by its
data; the script adds that header to the offset. Needs root (via sudo).

## Step 3: Back up

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-var.sh" --var <Name-GUID> backup --out <Name>.before.bin
```

Copy the backup off the machine as well.

## Step 4: Check that writes are accepted

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-var.sh" --var <Name-GUID> noop
```

This writes the variable back unchanged and confirms the content is
identical. If the write is refused, the firmware locks the variable and the
option cannot be changed from the OS.

## Step 5: Set the value (ask first)

Writing a setup variable is a firmware change that can stop the machine from
booting until its settings are reset. Confirm with the user, then:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-var.sh" --var <Name-GUID> --offset 0x4 --data-size 0x6EC --product <DMI product> --bios <version> --allowed 0,3,4 set 4
cmp -l <Name>.before.bin /sys/firmware/efi/efivars/<Name-GUID>   # exactly one line expected
```

Safety properties of the script:

- It refuses unless the DMI product, BIOS version and variable size match.
- It refuses unless the value is among the form's options.
- It refuses if more bytes than `--size` would change.
- It writes attributes and data in one `write()`, after `chattr -i`.

The firmware reads the variable at power-on, so the change applies after a
reboot. Re-run `show` after the reboot: some firmware resets a value it
considers invalid.

To undo: `setup-var.sh --var <Name-GUID> restore <Name>.before.bin`, then
reboot.

## Gotchas

- `cmp` exits 1 when files differ. Under `set -o pipefail` an unguarded
  `cmp | wc -l` aborts the script before the write. The script guards it; keep
  the guard if you adapt it.
- efivarfs files are immutable until `chattr -i`; a write without it fails
  with "Operation not permitted".
- Offsets come from the form for **one BIOS version**. Re-derive them after a
  firmware update.
- Worked example (Huawei MateBook X Pro 2020, BIOS 1.26): the form excerpt in Step 1;
  the efivarfs file was 1776 bytes (4 + 0x6EC); `noop` was accepted; `set 4`
  changed exactly file byte 9 (1-based, data offset 0x4); the laptop rebooted
  normally and kept the value. Whether Deep Sx changed its drain had not been
  measured when this skill was written.
