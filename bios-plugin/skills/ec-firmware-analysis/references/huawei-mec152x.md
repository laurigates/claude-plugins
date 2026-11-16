# Worked example: Huawei MateBook X Pro 2020 EC (MEC152x, EC 1.26)

Machine: DMI `MACHC-WAX9`, Insyde BIOS 1.26. Symptom: 110–255 mW drain while
powered off, measured from the battery gauge across shutdowns. The figure was
lower after a shutdown from BIOS setup, but still far above a healthy off
state.

## Locating and verifying the image

- In the vendor capsule, the BIOS region holds the EC image at region offset
  0x200000. The capsule's `platform.ini` has `[Region] ME=0, EC=1`, so the
  update rewrites the EC.
- In the 16 MB flash dump the `PHCM` header is at 0x600000 (BIOS region
  0x400000 + 0x200000). The dump matched the capsule's EC image byte for byte.
- Header: load 0x000B0000, entry 0x000B0009, payload 0x30000 bytes at +0x80,
  trailer at flash 0x630080. Both SHA-256 values matched and both signature
  fields were zero (`mec-image-check.py`: `STATUS=OK`, unsigned).
- Core: Microchip MEC152x-family Cortex-M4F. Huawei LiteOS (`LOS_TaskLock()`).

## The S5 kill routine (static analysis, Ghidra)

A 1 Hz EC soft timer, started on entering S5, runs `S5Kill_tick` (0xBEE94).
The 1 s rate is inferred from the 1000-tick timer and the log intervals.

- **After 10 ticks:** PCH-side rails off, including VSUS_ON (GPIO242). The
  routine logs "S5 10S Kill - PCH OFF". The EC keeps running.
- **"EC OFF"** (clears the VCI latch at 0x4000AE00) happens only when a second
  counter reaches zero. It starts at **86400** (24 h) and counts down once per
  tick while `AC_IN_OK_N` (GPIO162) reads battery. It **reloads to 86400 on
  every tick AC is present**.
- **The constant** 86400 (`80 51 01 00`) appears exactly twice, at 0xBEFF8 and
  0xBF380: the literal pools of the countdown and its reset function. In the
  flash dump these are 0x60F078 and 0x60F400.
- **Other conditions that block EC OFF:**
  - an auto-power-on flag (EC2 command 0xD0)
  - USB-C PD over-temperature protection
  - the power button held

Host-side knobs that turned out **not** to matter:

- `_PTS` sends nothing to the EC; the EC sees S5 only through the SLP pins
  and virtual wires.
- WMI command 0x6A (`PAFF`) is a temporary "ignore power button" mask.
- Command 0x95 (`CUSTOM_ENABLE_LID_AWAKE`) affects only keyboard wake from S3.
- The kill path does not use the Deep Sx handshake (inferred from code).

What it predicts:

- On battery, the drain runs for 24 h after each shutdown, then drops to
  near zero: about 2.6–6.1 Wh per shutdown at the measured rate.
- On AC, the EC never powers off.

**Status when this was written:** the 48 h soak that would confirm the
prediction had not been run. Treat the 24 h behaviour as inferred from code.

## Evidence the EC log would give

The EC writes boot events to an SRAM ring that is lost at EC OFF. On the next
boot:

- log ID 0x191 ("press pwrbtn EC first power on"): the EC had powered off
- log ID 0x409 ("EC no power down: S5 press pwrbtn"): it stayed up

Reading the ring from the OS goes through a vendor WMI method that triggers an
SMI. That was not done.

## Patch feasibility (read-only checks)

- EC image unsigned; Boot Guard off (MSR 0x13A = 0).
- Verified full flash backup taken.
- PR1 write-protects the EC region with `FLOCKDN=1`, so a patch needs an
  external SPI programmer.
- The patch would replace the two 86400 literals and recompute the trailer
  hash at 0x630080. **Not attempted.**
