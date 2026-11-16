# BIOS Plugin

Workflows for BIOS/UEFI firmware on laptops and desktops: getting the vendor's
firmware when its support site no longer lists it, and installing it from Linux
when the vendor does not publish to the LVFS.

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

The skills grew out of a 2026-11 investigation on a Huawei MateBook X Pro 2020
whose support page had lost its BIOS downloads; the worked examples come from
it.

## Installation

```bash
claude plugin install bios-plugin@laurigates-claude-plugins
```

## License

MIT
