# Apptainer — Reference

## Unprivileged Install Without `rpm2cpio`

The official installer
(`https://raw.githubusercontent.com/apptainer/apptainer/main/tools/install-unprivileged.sh`)
downloads Apptainer and its dependencies as RPMs from EPEL and Rocky Linux and
unpacks each with `curl … | rpm2cpio - | cpio -idum`. It requires `curl`,
`rpm2cpio` and `cpio` on `PATH`. Debian, Ubuntu and Pop!_OS ship `cpio` but not
`rpm2cpio`, and installing the `rpm2cpio` package needs root — the thing this
path avoids.

`rpm2cpio` only has to strip the RPM lead and two headers and decompress the
payload, so a stdlib Python stand-in is enough. Put it on `PATH` ahead of the
installer:

```python
#!/usr/bin/env python3
# Minimal rpm2cpio: strip the RPM lead and headers, decompress the payload to stdout.
import bz2, gzip, lzma, subprocess, sys

src = sys.argv[1] if len(sys.argv) > 1 else "-"
data = sys.stdin.buffer.read() if src == "-" else open(src, "rb").read()
if data[:4] != b"\xed\xab\xee\xdb":
    sys.exit("rpm2cpio: not an RPM")


def header_end(off, pad):
    if data[off:off + 3] != b"\x8e\xad\xe8":
        sys.exit("rpm2cpio: bad header magic")
    nindex = int.from_bytes(data[off + 8:off + 12], "big")
    hsize = int.from_bytes(data[off + 12:off + 16], "big")
    end = off + 16 + 16 * nindex + hsize
    return (end + 7) & ~7 if pad else end  # the signature header is padded to 8 bytes


payload = data[header_end(header_end(96, True), False):]
out = sys.stdout.buffer
if payload[:6] == b"\xfd7zXZ\x00":
    out.write(lzma.decompress(payload))
elif payload[:4] == b"\x28\xb5\x2f\xfd":  # zstd (EL9+); needs the zstd CLI
    out.write(subprocess.run(["zstd", "-dc"], input=payload, capture_output=True, check=True).stdout)
elif payload[:2] == b"\x1f\x8b":
    out.write(gzip.decompress(payload))
elif payload[:3] == b"BZh":
    out.write(bz2.decompress(payload))
else:
    out.write(payload)
```

Then download the installer, read it, and run it into a directory on a disk
with room (the install is ~150 MB; keep it off a nearly full root):

```sh
mkdir -p /big/disk/opt/bin && install -m 755 rpm2cpio /big/disk/opt/bin/
curl -fsSL -o install-unprivileged.sh https://raw.githubusercontent.com/apptainer/apptainer/main/tools/install-unprivileged.sh
PATH=/big/disk/opt/bin:$PATH bash install-unprivileged.sh -e /big/disk/opt/apptainer
/big/disk/opt/apptainer/bin/apptainer --version
```

The installer defaults to EL8 packages (the widest glibc compatibility), whose
payloads are xz — handled by `lzma` with no extra tools. `-e` shows download
errors and retries, which are otherwise silent.

Observed 2026-10-23 on Pop!_OS 22.04, kernel 6.17: Apptainer 1.5.4-1.el8
installed this way ran `colmap/colmap` (CUDA) with `--nv` on an RTX 4090.

## Choosing a Runtime on a Given Host

| Host situation | Pick |
|---|---|
| Linux + NVIDIA, root available, distro podman ≥ 4.1 | Podman + `nvidia-ctk cdi generate` — full isolation and networking |
| Linux + NVIDIA, distro podman < 4.1 (Ubuntu 22.04 ships 3.4.4) or no root | Apptainer — `--nv` needs no toolkit |
| macOS | Docker via OrbStack — no CUDA; CPU-side stages and tests only |
| Kubernetes / Argo | The same OCI image by digest; the cluster runtime runs it |

Podman's CDI device syntax (`--device nvidia.com/gpu=all`) arrived in podman
4.1; verify against the installed version (`podman --version`) before planning
on it.
