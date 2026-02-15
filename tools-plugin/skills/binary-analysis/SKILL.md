---
model: haiku
name: binary-analysis
description: Reverse engineering and binary exploration using strings, binwalk, hexdump, and related tools.
allowed-tools: Bash(file *), Bash(xxd *), Bash(hexdump *), Bash(strings *), Bash(objdump *), Bash(readelf *), Bash(nm *), Read, Grep, Glob
created: 2025-12-27
modified: 2025-12-27
reviewed: 2025-12-27
---

# Binary Analysis

Tools for exploring and reverse engineering binary files, firmware, and unknown data.

## Quick Reference

| Tool | Purpose | Install |
|------|---------|---------|
| `strings` | Extract printable text from binaries | Built-in (binutils) |
| `binwalk` | Firmware analysis, file extraction | `pip install binwalk` or `cargo install binwalk` |
| `hexdump` | Hex/ASCII dump | Built-in |
| `xxd` | Hex dump with reverse capability | Built-in (vim) |
| `file` | Identify file type | Built-in |

## strings - Extract Text from Binaries

Find human-readable strings embedded in binary files.

```bash
# Basic usage - find all printable strings (min 4 chars)
strings binary_file

# Set minimum string length
strings -n 10 binary_file          # Only strings >= 10 chars

# Show file offset of each string
strings -t x binary_file           # Hex offset
strings -t d binary_file           # Decimal offset

# Search for specific patterns
strings binary_file | grep -i password
strings binary_file | grep -E 'https?://'
strings binary_file | grep -i api_key

# Wide character strings (UTF-16)
strings -e l binary_file           # Little-endian 16-bit
strings -e b binary_file           # Big-endian 16-bit
strings -e L binary_file           # Little-endian 32-bit

# Scan entire file (not just initialized data sections)
strings -a binary_file
```

**Common discoveries with strings:**
- Hardcoded credentials, API keys
- URLs and endpoints
- Error messages (hints at functionality)
- Library versions
- Debug symbols and function names
- Configuration paths

## binwalk - Firmware Analysis

Identify and extract embedded files, analyze entropy, find hidden data.

```bash
# Signature scan - identify embedded files/data
binwalk firmware.bin

# Extract all identified files
binwalk -e firmware.bin            # Extract to _firmware.bin.extracted/
binwalk --extract firmware.bin     # Same as -e

# Recursive extraction (extract files within extracted files)
binwalk -Me firmware.bin

# Entropy analysis - find compressed/encrypted regions
binwalk -E firmware.bin            # Generate entropy graph
binwalk --entropy firmware.bin

# Opcode analysis - identify CPU architecture
binwalk -A firmware.bin
binwalk --opcodes firmware.bin

# Raw byte extraction at offset
binwalk --dd='type:extension' firmware.bin

# Specific signature types
binwalk --signature firmware.bin   # File signatures only
binwalk --raw='\\x1f\\x8b' firmware.bin  # Search for gzip magic bytes
```

**binwalk output interpretation:**
```
DECIMAL       HEXADECIMAL     DESCRIPTION
--------------------------------------------------------------------------------
0             0x0             TRX firmware header
28            0x1C            LZMA compressed data
1835008       0x1C0000        Squashfs filesystem, little endian
```

## hexdump / xxd - Raw Hex Analysis

```bash
# Hex + ASCII dump
hexdump -C binary_file
xxd binary_file

# Dump specific byte range
xxd -s 0x100 -l 256 binary_file    # 256 bytes starting at offset 0x100

# Just hex, no ASCII
hexdump -v -e '/1 "%02x "' binary_file

# Create hex dump that can be reversed
xxd binary_file > hex.txt
xxd -r hex.txt > reconstructed_binary

# Find specific bytes
xxd binary_file | grep "504b"      # Look for PK (ZIP signature)
```

## file - Identify File Types

```bash
# Basic identification
file unknown_file
file -i unknown_file               # MIME type

# Check multiple files
file *

# Follow symlinks
file -L symlink
```

## Common Analysis Workflows

### Unknown Binary Exploration
```bash
# 1. Identify file type
file mystery_file

# 2. Check for embedded files
binwalk mystery_file

# 3. Extract strings
strings -n 8 mystery_file | head -100

# 4. Look at hex header
xxd mystery_file | head -20

# 5. Check entropy (compressed/encrypted?)
binwalk -E mystery_file
```

### Firmware Analysis
```bash
# 1. Initial scan
binwalk firmware.bin

# 2. Extract everything
binwalk -Me firmware.bin

# 3. Explore extracted filesystem
find _firmware.bin.extracted -type f -name "*.conf"
find _firmware.bin.extracted -type f -name "passwd"

# 4. Search for secrets
grep -r "password" _firmware.bin.extracted/
strings -n 10 firmware.bin | grep -i -E "(pass|key|secret|token)"
```

### Finding Hidden Data
```bash
# Check for data after end of file
binwalk -E file.jpg               # Entropy spike at end = appended data

# Look for embedded archives
binwalk file.jpg | grep -E "(Zip|RAR|7z|gzip)"

# Extract with offset
dd if=file.jpg of=hidden.zip bs=1 skip=12345
```

## File Signatures (Magic Bytes)

| Signature | Hex | File Type |
|-----------|-----|-----------|
| `PK` | `50 4B 03 04` | ZIP archive |
| `Rar!` | `52 61 72 21` | RAR archive |
| `7z` | `37 7A BC AF` | 7-Zip |
| `ELF` | `7F 45 4C 46` | Linux executable |
| `MZ` | `4D 5A` | Windows executable |
| `PNG` | `89 50 4E 47` | PNG image |
| `JFIF` | `FF D8 FF E0` | JPEG image |
| `sqsh` | `73 71 73 68` | SquashFS |
| `hsqs` | `68 73 71 73` | SquashFS (LE) |

## Tips

- **Start with entropy**: High entropy = compressed or encrypted
- **Look for strings first**: Often reveals purpose quickly
- **Check file headers**: First 16 bytes often identify format
- **Use recursive extraction**: Firmware often has nested archives
- **Save offsets**: Note interesting locations for targeted extraction
