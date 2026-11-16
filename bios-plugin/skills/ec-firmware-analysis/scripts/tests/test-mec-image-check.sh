#!/usr/bin/env bash
# Offline test for mec-image-check.py: a synthetic unsigned MEC image must pass,
# and the same image with one payload byte changed must fail.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../mec-image-check.py"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

python3 -I - "$tmp/good.bin" "$tmp/bad.bin" <<'EOF'
import hashlib, struct, sys
payload = bytes((i * 7) & 0xff for i in range(0x400))          # 16 x 64 bytes
hdr = bytearray(b"PHCM\0\x05\x00\x03")
hdr += struct.pack("<II", 0x000B0000, 0x000B0009)
hdr += struct.pack("<H", len(payload) // 64) + b"\0\0"
hdr += struct.pack("<I", 0x80)
hdr += bytes(0x40 - len(hdr))
hdr += hashlib.sha256(hdr).digest() + bytes(32)
img = bytes(0x100) + hdr + payload + hashlib.sha256(payload).digest() + bytes(32) + b"\xff" * 64
open(sys.argv[1], "wb").write(img)
bad = bytearray(img); bad[0x100 + 0x80 + 5] ^= 1
open(sys.argv[2], "wb").write(bad)
EOF

pass=0 fail=0
expect() {  # $1 description, $2 text to search, $3 pattern
  if grep -q -- "$3" <<<"$2"; then pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi
}
good=$(python3 -I "$tool" "$tmp/good.bin" --base 0x600000 || true)
expect "good image passes" "$good" "STATUS=OK"
expect "header found at base+0x100" "$good" "PHCM at 0x600100"
expect "reported unsigned" "$good" "zero (unsigned)"
bad=$(python3 -I "$tool" "$tmp/bad.bin" || true)
expect "tampered payload fails" "$bad" "PAYLOAD_SHA256=MISMATCH"
expect "tampered image status" "$bad" "STATUS=MISMATCH"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
