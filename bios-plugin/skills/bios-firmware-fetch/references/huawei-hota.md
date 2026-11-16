# Huawei HOTA update service

Huawei's PC Manager and its DriverTools component fetch drivers and BIOS
updates from a service Huawei calls HOTA. This file records what is known
about it, and which parts were verified.

## Where the endpoint comes from

A decompiled copy of Huawei DriverTools is on GitHub as
`sv99/HuaweiDriverTools`. Three files in it give the request:

| File | Gives |
|---|---|
| `hotaURL.json` | The path `/hid_and_common/v2/CheckEx.action?latest=true&verType=true&defenceHijack=true` |
| `nk-grs/grs-user/router/grs_app_global_route_config.json` | Service `com.huawei.drivertools` routes to `https://update-dre.platform.hicloud.com` (Europe) and `https://update-drcn.platform.hicloud.com` (China) |
| `driverCFG/type/<model>/param.json` | Per-model component IDs and the `DeviceName`. For `MateBook X Pro(MACHC)`, BIOS is componentID `23` with DeviceName `MachC` |

## Request

`POST` with `Content-Type: application/json` to the host plus the path:

```json
{
  "components": [{"PackageVersionCode": "1.0.0.0", "componentID": "23", "PackageName": "BIOS"}],
  "rules": {"C_version": "C233", "Language": "en-US", "OS": "Windows",
            "deviceId": "<random 16 hex>", "DeviceName": "MachC"}
}
```

`PackageVersionCode` 1.0.0.0 asks for anything newer than nothing, so the
answer is the newest package. `deviceId` is random; nothing about the
requesting machine is sent. `C_version` values C233, C432 and C00 returned the
same answer for MachC.

## Response

```json
{"status":"0","components":[{"name":"OTA-MachC-BIOS-1.26","version":"1.26",
  "createTime":"2023-04-09T16:00:00+0000",
  "url":"http://update.dbankcdn.com/download/data/pub_13/HWHOTA_hota_900_9/62/v3/<id>/",
  "reserveUrl":"updatessl.dbankcdn.com","componentID":23}]}
```

An unknown DeviceName returns `{"status":"1"}` with no components.

Under the returned `url`:

| Path | Content |
|---|---|
| `full/filelist.xml` | Manifest. Companions (`changelog.xml`) are `<files>/<file>` entries; the package is a `<remotefiles>/<remotefile>` entry with `md5`, `sha256`, `size`, `url` (Alibaba Cloud OSS, Hangzhou) and `urlOversea` (OSS, Frankfurt) |
| `full/changelog.xml` | Release notes per language; also declares `needReboot` and the component name and version |
| `full/update.zip` | Returns 403; download from the manifest's `url`/`urlOversea` instead |

The package file sits on an OSS bucket, not a Huawei domain. What ties it to
Huawei is the manifest on `update.dbankcdn.com`: its sha256 and size must
match the downloaded file.

## Package contents (MachC BIOS 1.26)

`update.zip` holds `MachC_BIOS_1.26.exe`, an NSIS installer. `7z` lists and
extracts it without running it. Inside: `UEFI_FW.bin` (the capsule, a signed
PE with sections `.text`, `UEFI_FW`, `.xdata`, `.reloc`, `CERTIFICATE`),
`MachineTypeList.xml` (maps type `MachC` to `MACHC-WAX9`, a table shared
across Huawei installers), `CapAgent.efi`, a Windows driver and helper tools.
`UEFI_FW.bin` contains the machine's ESRT System Firmware GUID
`5f84a7ba-5544-4ddf-9622-1704daa3f7a9`.

## The support site

`consumer.huawei.com/<cc>/support/laptops/matebook-x-pro-2020/` returned 404
in every region tried (2026-11). The site's product API still returns the
model's offerings, but its knowledge-base listing for them names only PC
Manager, DriverTools, the fingerprint and hotkey drivers and Windows repair
tools: no BIOS.

## Verified, and not

| Claim | Status (2026-11-16) |
|---|---|
| Request shape returns `OTA-MachC-BIOS-1.26` from `update-dre` | Verified by `scripts/huawei-hota-query.sh MachC` |
| Unknown DeviceName returns `status 1` | Verified |
| Downloaded `update.zip` matches the live manifest's sha256 and size | Verified by `scripts/verify-download.sh` |
| componentID 23 means BIOS on other Huawei models | Unverified: read each model's `param.json` |
| The capsule installs and flashes correctly through fwupd | Not yet performed (pending at time of writing) |
