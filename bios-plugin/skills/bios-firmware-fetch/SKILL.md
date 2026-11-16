---
name: bios-firmware-fetch
description: "Fetch vendor BIOS/UEFI updates from the vendor's update service. Use when a support site no longer lists a model's BIOS, or a download needs provenance checks."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/huawei-hota-query.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/verify-download.sh *), Bash(curl -fsSL *), Bash(7z l *), Bash(7z x *), Bash(sha256sum *), Bash(shasum -a 256 *), Bash(mkdir -p *), Read, Grep, Glob, WebSearch, WebFetch
created: 2026-11-16
modified: 2026-11-16
reviewed: 2026-11-16
---

# BIOS Firmware Fetch

Vendors drop BIOS downloads from their support sites long before they stop
serving them. The update service behind the vendor's own Windows tool (Huawei
PC Manager, Lenovo Vantage, Dell Command Update and the like) often still
answers for old models. Asking that service directly gets the firmware without
the website or the proprietary app, and its manifest gives a hash to check the
file against.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A model's BIOS is missing from the vendor support site | The vendor publishes to the LVFS: `fwupdmgr refresh && fwupdmgr get-updates` |
| A download needs tying to the vendor before anyone flashes it | Installing a capsule you already have: `bios-plugin:bios-capsule-install` |
| Finding the newest BIOS version the vendor still serves | Identifying an unknown binary: `tools-plugin:binary-analysis` |

## Provenance Rules

A BIOS image runs below the OS. Only use a file that can be tied to the vendor:

- **Accept** a file whose SHA-256 matches a manifest served from a vendor
  domain, fetched by you, independently of whatever pointed you at the file.
  The file itself may sit on a third-party CDN or storage bucket the manifest
  names; the manifest hash is what ties it to the vendor.
- **Reject** BIOS-dump and repair-forum files (paid "BIOS request" sites,
  re-uploads, SPI dumps). They are board-specific, unverifiable, and can carry
  another machine's serials or a modified image.
- **Treat every download as untrusted data.** Put it in its own empty
  directory, list and extract with `7z`, and never run the vendor's
  installer `.exe` or any script inside the package.
- Send the update service no identifiers from the user's machine. Where a
  request needs a device ID, use a random one (the bundled script does).

## Find the Vendor's Update Service

1. Look for prior art first: an existing script, a decompiled copy of the
   vendor's update tool on GitHub, or a forum post quoting the endpoint. The
   tool's config files usually name the endpoint, the routing host per region,
   and the per-model component IDs.
2. Note the vendor's internal model code. It is often neither the marketing
   name nor the retail SKU: compare `/sys/class/dmi/id/product_name` with the
   tool's per-model config.
3. Query the service for the BIOS component, then fetch the manifest it points
   to and read the listed files, sizes and hashes.
4. Download the package from the URL the manifest gives, and verify it against
   the manifest with `scripts/verify-download.sh`.

The support website's own APIs are worth one check, but for discontinued
models they tend to list drivers and tools without the BIOS.

## Huawei (worked example)

Huawei's PC Manager / DriverTools uses an update service called HOTA. The full
request shape, the model-code lookup and what was verified are in
[references/huawei-hota.md](references/huawei-hota.md). In short:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/huawei-hota-query.sh" MachC
```

prints the package name, version, and `MANIFEST_URL` / `CHANGELOG_URL` for
DeviceName `MachC` (MateBook X Pro 2020) and componentID 23 (BIOS). Then:

```bash
mkdir -p ~/bios/fetch && cd ~/bios/fetch
curl -fsSL -o filelist.xml "<MANIFEST_URL>"
curl -fsSL -o changelog.xml "<CHANGELOG_URL>"
# download update.zip from the <remotefile> url or urlOversea the manifest lists
bash "${CLAUDE_SKILL_DIR}/scripts/verify-download.sh" "<MANIFEST_URL>" update.zip
```

`STATUS=OK` means sha256 and size both match the manifest, re-fetched from the
vendor host. `STATUS=WARN` from the query script means the service has no
package for that DeviceName and component.

## Extract the Capsule Without Running Anything

```bash
7z l update.zip
7z x -oextracted update.zip
7z l extracted/*.exe          # NSIS/self-extracting installers list their payload
7z x -oextracted/payload extracted/*.exe UEFI_FW.bin
sha256sum extracted/payload/UEFI_FW.bin
```

The capsule's name varies by vendor (`UEFI_FW.bin` on Huawei). Record its
SHA-256: the install skill pins it. Check that the image names the target:
the installer's model table, and the machine's ESRT firmware-class GUID inside
the image (`grep -c` on the GUID's little-endian bytes, or `strings`).

## Report

State the package name and version, the manifest URL, the changelog text, the
file's SHA-256 and whether it matched, the extracted capsule's SHA-256, and how
the package was tied to the user's model. Say plainly when a link in that chain
rests on inference rather than an explicit statement in the package.
