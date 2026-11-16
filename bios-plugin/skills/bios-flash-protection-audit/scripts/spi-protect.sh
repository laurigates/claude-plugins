#!/usr/bin/env bash
# Read-only audit of the Intel PCH SPI controller's flash protection: BIOS
# write enable/lock bits, the flash lock-down bit, protected ranges (PR0-PR4),
# the BIOS master's region access (FRAP) and the flash region map (FREG0-5),
# plus Intel Boot Guard status. Reads PCI config space, the SPI controller's
# MMIO registers through /dev/mem, and one MSR. Never touches the flash chip.
#
# Register offsets are those of the Intel 100- to 400-series PCH SPI
# controller (Sunrise Point through Comet Point). Verified on Comet Lake LP
# (8086:02a4). On other generations confirm the offsets in the PCH datasheet
# before trusting the output.
#
# Usage: spi-protect.sh [--dev BB:DD.F]   (default: auto-detect)
# Needs root (run with sudo), setpci (pciutils), python3, and for the Boot
# Guard line rdmsr (msr-tools) with the msr module loaded.
set -euo pipefail

dev=""
[ "${1:-}" = --dev ] && dev=$2

if [ -z "$dev" ]; then
  # Intel SPI flash controller: vendor 8086, class 0c80 (serial bus, other).
  dev=$(lspci -Dn -d 8086::0c80 | awk '{print $1}' | while read -r d; do
          lspci -s "$d" | grep -qi 'SPI' && echo "$d"; done | head -1)
  [ -n "$dev" ] || { echo "no Intel SPI controller found (try --dev)"; exit 1; }
fi
echo "=== DEVICE ==="
lspci -nn -s "$dev"

echo "=== BIOS_CNTL ==="
bc=$(setpci -s "$dev" dc.b)
printf 'BIOS_CNTL=0x%s BIOSWE=%d BLE=%d SMM_BWP=%d\n' "$bc" \
  $(( 0x$bc & 1 )) $(( (0x$bc >> 1) & 1 )) $(( (0x$bc >> 5) & 1 ))

bar=$(( 0x$(setpci -s "$dev" 10.l) & 0xFFFFF000 ))
printf 'SPIBAR=0x%x\n' "$bar"

python3 -I - "$bar" <<'EOF'
import mmap, os, struct, sys
bar = int(sys.argv[1])
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=bar)
r32 = lambda o: struct.unpack_from("<I", m, o)[0]

print("=== HSFS ===")
hsfs = r32(0x04)
print(f"HSFS=0x{hsfs:08x} FLOCKDN={(hsfs >> 15) & 1} FDV={(hsfs >> 14) & 1}")

print("=== PROTECTED RANGES ===")
for i in range(5):
    pr = r32(0x84 + 4 * i)
    base, limit = (pr & 0x7FFF) << 12, (((pr >> 16) & 0x7FFF) << 12) | 0xFFF
    used = "" if pr else " (unused)"
    print(f"PR{i}=0x{pr:08x} RP={(pr >> 15) & 1} WP={(pr >> 31) & 1} 0x{base:07x}-0x{limit:07x}{used}")

print("=== REGIONS ===")
frap = r32(0x50)
print(f"FRAP=0x{frap:08x} BIOS_master_read=0x{frap & 0xff:02x} BIOS_master_write=0x{(frap >> 8) & 0xff:02x}")
names = ["Descriptor", "BIOS", "ME", "GbE", "PlatformData", "Device/EC"]
for i, name in enumerate(names):
    fr = r32(0x54 + 4 * i)
    base, limit = (fr & 0x7FFF) << 12, (((fr >> 16) & 0x7FFF) << 12) | 0xFFF
    state = " (unused)" if base > limit else ""
    rd = "r" if (frap >> i) & 1 else "-"
    wr = "w" if (frap >> (8 + i)) & 1 else "-"
    print(f"FREG{i}={name:12s} 0x{base:07x}-0x{limit:07x} BIOS_master={rd}{wr}{state}")
EOF

echo "=== BOOT GUARD ==="
if command -v rdmsr >/dev/null 2>&1; then
  modprobe msr 2>/dev/null || true
  v=$(rdmsr -0 0x13a 2>/dev/null || echo unreadable)
  # MSR 0x13A (BOOT_GUARD_SACM_INFO): all zero when no Boot Guard ACM ran.
  echo "MSR_0x13A=0x$v"
else
  echo "MSR_0x13A=skipped (install msr-tools for rdmsr)"
fi
