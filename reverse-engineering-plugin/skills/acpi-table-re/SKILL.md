---
name: acpi-table-re
description: Reverse-engineer ACPI tables (DSDT/SSDT) with iasl. Use when investigating a device's ACPI definition — find a device by _ADR/_HID, read a _DSM, or map wake sources (_PRW/GPE) for suspend/drain work. Covers iasl decompilation, the live tables on Linux, and the methods to grep.
user-invocable: false
allowed-tools: Bash(iasl *), Bash(acpixtract *), Bash(ls /sys/firmware/acpi/tables*), Bash(rg *), Read, Grep, Glob
created: 2026-11-17
modified: 2026-11-17
reviewed: 2026-11-17
---

# ACPI Table Reverse-Engineering

ACPI tables (DSDT + the SSDTs) are the firmware's description of every onboard
device, its resources, power/wake behaviour, and vendor `_DSM` entry points.
Decompiling them answers "what is this device, how is it wired, how does it wake"
without guessing from the device menu.

## Get the tables and decompile

```sh
# Live, on a Linux box (names visible without root; bytes need root):
ls /sys/firmware/acpi/tables/            # DSDT SSDT1..N FACP FPDT ... (+ dynamic/)
sudo cp /sys/firmware/acpi/tables/SSDT9 /tmp/ && iasl -d /tmp/SSDT9   # -> SSDT9.dsl

# From a firmware dump: extract the BIOS region first (see firmware-dump-region-map),
# then iasl -d the .aml tables. Or carve live AML with acpixtract.
iasl -d *.aml                            # batch; re-run singly if one truncates
```

`iasl` ships in the `acpica`/`acpica-tools` package (`iasl`, `acpixtract`). A
batch `iasl -d *.aml` can exit non-zero on external-symbol warnings while still
emitting `.dsl` — re-run the stragglers individually.

## Find a device

```sh
rg -n 'Device \(|_ADR|_HID|_CID' DSDT.dsl        # device tree
rg -n '0x001F0005' DSDT.dsl                       # by PCI _ADR (seg/bus:dev.fn)
rg -n '"GXFP51B7"|EisaId' DSDT.dsl                # by _HID
```

- `_ADR` = address on the parent bus (PCI `dev<<16|fn`); `_HID`/`_CID` = the
  ACPI/PNP id a driver binds. A `_HID` returned from a **method** (not a `Name`)
  is chosen at runtime from a firmware variable — the actual id is in an NVS/EC
  field, read it live (`/sys/bus/.../modalias`).
- `_STA` gates presence; a device can be defined but return 0 (absent) on this
  SKU. `_INI`, `_CRS` (current resources: IRQ/GPIO/memory), `_DSM` (vendor
  device-specific method, keyed by a UUID + function index).

## Map wake sources (suspend / drain work)

```sh
rg -n '_PRW' DSDT.dsl                              # Power Resources for Wake
rg -n 'GPRW|_GPE|Notify' DSDT.dsl
```

`_PRW` returns `{GPE-bit, lowest-sleep-state}` — the devices armed to wake the
system and from how deep. A shared GPE bit (many devices `Return (GPRW(0x6D,…))`)
is the firmware funnelling USB/PCIe wake through one line; watch its counter at
`/sys/firmware/acpi/interrupts/gpe<NN>` for a spurious-wake storm. OEM
"instant-wake" fixes mask specific GPEs — a clue to which wake sources misbehave.

## Vendor `_DSM` methods

A `_DSM` is `(UUID, rev, function-index, args)`. Function 0 returns a bitmap of
supported functions; the rest are vendor-defined (e.g. an EC-command doorbell, a
blob read). Read the method body to learn the real action — often it just pokes
an EC command or returns an operation-region field. Cross-check against the
driver: an `_DSM` guarded by `CondRefOf(\_SB...X)` that names a path which
doesn't exist (a firmware typo, e.g. `H_EC` vs `HWEC`) is **dead code** that
never executes, however much the driver seems to call it.

## Related

- `firmware-dump-region-map` — extract the BIOS region to get the `.aml` tables.
- `ghidra-headless-decompile` — pair the ACPI view with the driver that calls it.
- `linux-plugin` / `macos-plugin` — platform power/suspend debugging that
  consumes these wake findings.
