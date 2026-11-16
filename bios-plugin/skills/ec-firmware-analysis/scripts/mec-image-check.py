#!/usr/bin/env python3
"""Find Microchip MEC EC boot images ("PHCM" headers) in a firmware or flash
dump and check their integrity fields.

Layout (Microchip MEC152x Boot ROM SPI image, as produced by ChromiumOS
chip/mchp/util/pack_ec.py and Microchip's SPI_image_gen):

  +0x00  "PHCM" tag
  +0x08  load address (LE32)      +0x0C  entry point (LE32)
  +0x10  payload length in 64-byte units (LE16)
  +0x14  payload offset from the header (LE32)
  +0x40  SHA-256 of header bytes 0x00-0x3F, then 32 bytes that hold zeros in
         an unsigned image (an ECDSA signature when signing is used)
  after the payload: SHA-256 of the payload, then 32 bytes (zeros if unsigned)

An unsigned image is protected only by the two SHA-256 values, so a modified
payload needs only its trailer hash recomputed. Whether the chip enforces
signatures is an OTP setting inside the EC; a chip that enforced them would
not boot an unsigned vendor image.

Usage: mec-image-check.py IMAGE [--base ADDR]
  --base  flash address of the file's first byte, for reporting (default 0)
Prints KEY=VALUE lines per image and STATUS=OK|MISMATCH|NONE. Reads only.
"""

import argparse
import hashlib
import struct
import sys


def check(data: bytes, off: int) -> dict:
    hdr = data[off : off + 0x80]
    load, entry = struct.unpack_from("<II", hdr, 0x08)
    units = struct.unpack_from("<H", hdr, 0x10)[0]
    pay_off = struct.unpack_from("<I", hdr, 0x14)[0]
    pay_len = units * 64
    hdr_hash_ok = hashlib.sha256(hdr[:0x40]).digest() == hdr[0x40:0x60]
    hdr_sig_zero = hdr[0x60:0x80] == bytes(32)
    p0 = off + pay_off
    payload = data[p0 : p0 + pay_len]
    trailer = data[p0 + pay_len : p0 + pay_len + 64]
    pay_hash_ok = (
        len(payload) == pay_len and hashlib.sha256(payload).digest() == trailer[:32]
    )
    pay_sig_zero = trailer[32:64] == bytes(32)
    return {
        "load": load,
        "entry": entry,
        "payload_offset": pay_off,
        "payload_len": pay_len,
        "trailer": p0 + pay_len,
        "header_hash_ok": hdr_hash_ok,
        "payload_hash_ok": pay_hash_ok,
        "unsigned": hdr_sig_zero and pay_sig_zero,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("image")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0)
    a = ap.parse_args()
    with open(a.image, "rb") as f:
        data = f.read()
    found = mismatch = 0
    pos = data.find(b"PHCM")
    while pos != -1:
        if pos + 0x80 <= len(data):
            r = check(data, pos)
            found += 1
            print(f"=== PHCM at 0x{a.base + pos:x} ===")
            print(f"LOAD=0x{r['load']:08x} ENTRY=0x{r['entry']:08x}")
            print(
                f"PAYLOAD=0x{a.base + pos + r['payload_offset']:x} LEN=0x{r['payload_len']:x} TRAILER=0x{a.base + r['trailer']:x}"
            )
            print(f"HEADER_SHA256={'ok' if r['header_hash_ok'] else 'MISMATCH'}")
            print(f"PAYLOAD_SHA256={'ok' if r['payload_hash_ok'] else 'MISMATCH'}")
            print(
                f"SIGNATURE_FIELDS={'zero (unsigned)' if r['unsigned'] else 'non-zero (signed or not this format)'}"
            )
            mismatch += not (r["header_hash_ok"] and r["payload_hash_ok"])
        pos = data.find(b"PHCM", pos + 4)
    print(f"IMAGES={found}")
    print("STATUS=" + ("NONE" if not found else "MISMATCH" if mismatch else "OK"))
    return 1 if mismatch or not found else 0


if __name__ == "__main__":
    sys.exit(main())
