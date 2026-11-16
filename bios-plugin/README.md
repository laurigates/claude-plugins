# BIOS Plugin

Workflows for BIOS/UEFI firmware on laptops and desktops: getting the vendor's
firmware when its support site no longer lists it, installing it from Linux
when the vendor does not publish to the LVFS, changing hidden setup options,
auditing and backing up the SPI flash, writing it with an external programmer,
and analysing the embedded controller firmware.

Vendors stop listing BIOS downloads for older models long before they stop
serving them: the update service behind the vendor's own Windows tool often
still answers. These skills query that service directly, tie the file to a
vendor-hosted manifest by hash, and package the capsule for fwupd, so neither
the vendor's website nor its proprietary app is needed.

Related skills elsewhere:

- `tools-plugin:binary-analysis` identifies unknown files and lists PE sections.
- `kernel-plugin` covers reporting a kernel problem upstream once firmware is
  ruled out.

## Skills

| Skill | Description |
|-------|-------------|
| `bios-firmware-fetch` | Find and download a vendor BIOS/UEFI update from the vendor's own update service, verify it against the vendor-hosted manifest, and extract the capsule image without running anything |
| `bios-capsule-install` | Install a vendor UEFI capsule from Linux through fwupd: ESRT and device checks, building the cabinet, relaxing `OnlyTrusted` for one install, pre-flight checks, and post-reboot verification |
| `bios-setup-variables` | Read or change hidden UEFI setup options from Linux through efivarfs, with offsets from the setup form (IFR), backups and a no-op write test |
| `bios-flash-protection-audit` | Read-only audit of Intel PCH SPI flash protection and Boot Guard, plus a verified full flash backup with flashrom |
| `bios-external-programmer` | Read or write the SPI flash in-circuit with flashrom and an ESP32-S3 serprog board (or Pico/CH341A): firmware build, wiring, safety, verify procedure |
| `ec-firmware-analysis` | Locate, verify and statically reverse-engineer the embedded controller firmware; check whether a patched Microchip MEC image would be accepted |
| `bios-update-diff` | Work out what a BIOS update changed (microcode, EC, ACPI tables, ME) from boot logs and the new image when the old image is gone |

The skills grew out of a 2026-11 investigation on a Huawei MateBook X Pro 2020
whose support page had lost its BIOS downloads; the worked examples come from
it.

## Installation

```bash
claude plugin install bios-plugin@laurigates-claude-plugins
```

## License

MIT
