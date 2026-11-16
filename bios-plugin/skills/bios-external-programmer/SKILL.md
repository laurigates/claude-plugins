---
name: bios-external-programmer
description: "Read or write a laptop's SPI flash in-circuit with flashrom, using an ESP32-S3 dev board as serprog programmer or a Pico/CH341A. Use when the OS cannot write the flash."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/build-xiao-serprog.sh *), Bash(flashrom --version), Bash(ls /dev/cu.usbmodem*), Bash(ls /dev/ttyACM*), Bash(sha256sum *), Bash(shasum -a 256 *), Bash(cmp *), Read, Grep, Glob, AskUserQuestion
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# BIOS External Programmer (in-circuit SPI flash)

When the chipset write-protects a flash region from the OS
(`bios-plugin:bios-flash-protection-audit` shows `WP=1` with `FLOCKDN=1`), the
only way to write it is a programmer clipped onto the chip. flashrom's
`serprog` protocol lets a cheap microcontroller board do that job.

> **Status:** the ESP32-S3 firmware from Step 1 compiles and has been checked by
> reading its source. **No in-circuit read or write with it has been verified
> yet.** The 16 MB write reported upstream was a 1.8 V chip at 250 kHz through
> a level shifter. Verify a read against a known backup before any write.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| The OS cannot write the flash region you need to change | The OS can write it: flashrom `-p internal` |
| Recovering a machine whose firmware no longer boots | Only reading is needed and the OS can read: `bios-plugin:bios-flash-protection-audit` |

## Choosing a programmer

| Board | Works? | Notes |
|---|---|---|
| ESP32-S3 (Seeed XIAO ESP32-S3, Waveshare ESP32-S3-Zero, …) | Yes, with [thisiseth/esp32-serprog](https://github.com/thisiseth/esp32-serprog) | 3.3 V logic, native USB Serial/JTAG (no baud limit). Needs ESP-IDF ≥ 6.0 and a pin edit |
| Raspberry Pi Pico (RP2040) | Yes, with pico-serprog (firmware and steps in the [libreboot SPI guide](https://libreboot.org/docs/install/spi.html)) | The best-trodden route; libreboot removed RP2350 support, so buy an RP2040 |
| Raspberry Pi (40-pin) | Yes, flashrom `linux_spi` via `/dev/spidev0.0` | 3.3 V native |
| CH341A | Yes, flashrom `ch341a_spi` | Some boards put 5 V on the data lines; use a 3.3 V-modified one |
| Arduino Nano/Uno | Possible (`frser-duino`) | 5 V logic needs dividers; its 3.3 V pin cannot power an in-circuit chip |
| CP2102, CH340 (USB-UART) | **No** | UART only; flashrom cannot drive SPI through them |

flashrom's `serprog` programmer is in Homebrew's flashrom (macOS and Linux)
and in distro packages, so the host side needs no source build.

## Step 1: Build the ESP32-S3 firmware

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/build-xiao-serprog.sh" ./esp32-serprog-build
```

The script:

1. Clones upstream at a pinned commit (`0ca3c7e`, 2026-07-23).
2. Applies [scripts/xiao-esp32s3-pins.patch](scripts/xiao-esp32s3-pins.patch):
   SCK D8/GPIO7, MISO D9/GPIO8, MOSI D10/GPIO9, CS D1/GPIO2. Upstream's
   default S3 pins (GPIO 2/40/41/42) are not all on XIAO pads.
3. Builds with ESP-IDF ≥ 6.0 (`IDF_PATH`, default `~/esp/esp-idf`).
4. Fails if the transport is not USB Serial/JTAG or Wi-Fi is on.

It prints the binaries' hashes and the flash offsets. On a XIAO **Sense**,
remove the camera/SD expansion board, whose SD slot shares GPIO7/8/9.

Flash the board (hold BOOT while plugging in if it does not enumerate):

```bash
cd ./esp32-serprog-build/xiao-serprog-out && python -m esptool --chip esp32s3 -p <port> -b 460800 --before default-reset --after hard-reset write-flash --flash-mode dio --flash-size 2MB --flash-freq 80m 0x0 bootloader.bin 0x8000 partition-table.bin 0x10000 main.bin
```

ESP-IDF v6 ships esptool v5 (`write-flash`, not `write_flash`). The port is
`/dev/cu.usbmodem*` on macOS and `/dev/ttyACM*` on Linux.

## Step 2: Wire it (SOP-8 25-series flash)

| Chip pin | Signal | XIAO pin | Note |
|---|---|---|---|
| 1 | CS# | D1 (GPIO2) | 47 Ω in series |
| 2 | SO / MISO | D9 (GPIO8) | 47 Ω in series |
| 3 | WP# | 3V3 | through 10 kΩ |
| 4 | GND | GND | |
| 5 | SI / MOSI | D10 (GPIO9) | 47 Ω in series |
| 6 | SCLK | D8 (GPIO7) | 47 Ω in series |
| 7 | HOLD# / RESET# | 3V3 | through 10 kΩ |
| 8 | VCC | 3V3 | one supply only |

Pin 1 is next to the dot on the package. A WSON-8 chip has the same pinout but
no legs, so a SOIC clip will not grip; use a pogo-pin probe or solder wires.

Safety order:

1. Disconnect the laptop's battery connector and remove the charger before
   clipping on.
2. The firmware drives the SPI pins as soon as it has power and never releases
   them (no `S_PIN_STATE`). **Unplug the clip before powering the laptop.**
3. Use one power source on VCC. If the chip ID reads as all 00 or FF, or
   reads differ, the laptop's 3.3 V rail is drawing current through VCC. Use a
   separate current-limited 3.3 V supply with a common ground.

## Step 3: Read, verify, and only then write

```bash
flashrom -p serprog:dev=<port>,spispeed=2M --flash-name
flashrom -p serprog:dev=<port>,spispeed=2M -r ext-1.bin
flashrom -p serprog:dev=<port>,spispeed=2M -r ext-2.bin
sha256sum ext-1.bin ext-2.bin <backup-from-the-os>.bin
```

- Several flashrom chip definitions can share one JEDEC ID. If flashrom asks,
  pick with `-c "<name>"` from its list, matching the part number printed on
  the chip.
- The two external reads must match each other. Compare them with the OS-side
  backup; differences limited to the UEFI variable store or ME data are
  expected if the machine booted in between.
- Raise `spispeed` (4M, 8M) only after reads match at the lower speed.

Writing is a separate decision, and needs the user's go-ahead:

```bash
flashrom -p serprog:dev=<port>,spispeed=2M -w patched.bin   # verifies automatically
flashrom -p serprog:dev=<port>,spispeed=2M -r after.bin && cmp after.bin patched.bin
```

Keep the original dump off the machine. Restoring it the same way is the
recovery path.

## Sources

- [thisiseth/esp32-serprog](https://github.com/thisiseth/esp32-serprog): transports, command set, pins in `src/serprog/main/main.c`.
- [Seeed XIAO ESP32-S3 pin multiplexing](https://wiki.seeedstudio.com/xiao_esp32s3_pin_multiplexing/).
- [flashrom serprog protocol](https://flashrom.org/supported_hw/supported_prog/serprog/serprog-protocol.html) and [in-system programming](https://www.flashrom.org/user_docs/in_system.html).
- [libreboot SPI guide](https://libreboot.org/docs/install/spi.html): series resistors, WP/HOLD pull-ups, CH341A 5 V warning.
