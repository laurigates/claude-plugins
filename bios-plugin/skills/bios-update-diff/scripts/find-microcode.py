#!/usr/bin/env python3
"""List Intel CPU microcode updates embedded in a firmware image.

Scans for the 48-byte Intel microcode update header: header version 1,
loader revision 1, a BCD date, a data/total size consistent with the file, and
a checksum of zero over the whole update. Prints offset, CPUID signature,
platform-flag mask, revision and date for each match.

Usage: find-microcode.py IMAGE [--cpuid 0x806EC]
Compare a revision with the kernel's `microcode: Updated early from: 0x...`
line for a boot under the same BIOS: that is the revision the BIOS loaded.
Reads only.
"""

import argparse
import struct
import sys


def is_bcd(v: int) -> bool:
    return all(((v >> s) & 0xF) <= 9 for s in range(0, 32, 4))


def scan(data: bytes):
    pos = 0
    while True:
        pos = data.find(b"\x01\x00\x00\x00", pos)
        if pos == -1 or pos + 48 > len(data):
            return
        hv, rev, date, sig, _cks, loader, pf, dsize, tsize = struct.unpack_from(
            "<9I", data, pos
        )
        if hv == 1 and loader == 1 and is_bcd(date):
            dsize = dsize or 2000
            tsize = tsize or 2048
            if 48 + dsize <= tsize <= len(data) - pos and tsize % 1024 == 0:
                words = struct.unpack_from(f"<{tsize // 4}I", data, pos)
                if sum(words) & 0xFFFFFFFF == 0:
                    y, m, d = date & 0xFFFF, date >> 24, (date >> 16) & 0xFF
                    yield pos, sig, pf, rev, f"{y:04x}-{m:02x}-{d:02x}", tsize
                    pos += tsize
                    continue
        pos += 4


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("image")
    ap.add_argument("--cpuid", type=lambda s: int(s, 0))
    a = ap.parse_args()
    with open(a.image, "rb") as f:
        data = f.read()
    n = 0
    for off, sig, pf, rev, date, size in scan(data):
        if a.cpuid is not None and sig != a.cpuid:
            continue
        n += 1
        print(
            f"offset=0x{off:x} cpuid=0x{sig:x} platform_flags=0x{pf:x} revision=0x{rev:x} date={date} size=0x{size:x}"
        )
    print(f"UPDATES={n}")
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main())
