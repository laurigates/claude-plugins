---
model: haiku
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
name: Network Monitoring
description: Real-time network traffic monitoring with bandwhich and Sniffnet. Per-process bandwidth tracking, connection analysis, and visual traffic inspection.
allowed-tools: Bash(iftop *), Bash(nethogs *), Bash(tcpdump *), Bash(ss *), Bash(netstat *), Read, Grep, Glob, TodoWrite
---

# Network Monitoring

Expert knowledge for real-time network traffic monitoring using modern Rust-based tools: bandwhich for CLI-based per-process bandwidth analysis and Sniffnet for visual traffic inspection.

## Core Expertise

### Why These Tools

| Tool | Type | Best For |
|------|------|----------|
| bandwhich | CLI | Per-process bandwidth, quick diagnostics, scripting |
| Sniffnet | GUI | Visual analysis, long-term monitoring, filtering |

### Key Advantages

- **Per-process visibility**: See which applications consume bandwidth (unlike traditional `iftop`)
- **Connection-level detail**: Track individual connections to remote hosts
- **Modern Rust performance**: Minimal overhead, safe memory handling
- **Cross-platform**: Works on Linux, macOS, Windows

### Privilege Requirements

Both tools require elevated privileges to capture network traffic:

```bash
# Run with sudo
sudo bandwhich

# Or grant capabilities (Linux, avoids sudo)
sudo setcap cap_net_raw,cap_net_admin+ep $(which bandwhich)
```

## Essential Commands

### bandwhich - CLI Bandwidth Monitor

#### Basic Usage

```bash
# Start monitoring (requires sudo or capabilities)
sudo bandwhich

# Monitor specific interface
sudo bandwhich -i en0
sudo bandwhich -i eth0

# Raw mode (no TUI, machine-readable)
sudo bandwhich -r

# Disable DNS resolution (faster startup)
sudo bandwhich -n
```

#### Output Modes

```bash
# Default TUI with three panels:
# - Processes (bandwidth by application)
# - Connections (bandwidth by socket)
# - Remote addresses (bandwidth by host)

# Raw output for scripting
sudo bandwhich -r
# Output: <interface>:<process>:<bytes_down>:<bytes_up>

# Combined options
sudo bandwhich -i en0 -n -r
```

#### TUI Navigation

| Key | Action |
|-----|--------|
| `Tab` | Switch between panels |
| `Up/Down` | Navigate rows |
| `q` | Quit |

### Sniffnet - GUI Traffic Monitor

#### Installation

```bash
# macOS
brew install sniffnet

# Cargo
cargo install sniffnet

# Or download from GitHub releases
# https://github.com/GyulyVGC/sniffnet/releases
```

#### Features

- Real-time traffic charts
- Filter by protocol, port, IP
- Domain and provider identification
- Geo-location of remote hosts
- Export reports

#### Launch

```bash
# GUI application (requires sudo or admin)
sudo sniffnet

# On macOS, may need to grant network access in System Preferences
```

## Common Patterns

### Diagnose High Bandwidth Usage

```bash
# Quick check: which process is using bandwidth?
sudo bandwhich -n

# Watch specific interface during download
sudo bandwhich -i en0
```

### Script-Friendly Monitoring

```bash
# Capture 10 seconds of raw data
sudo timeout 10 bandwhich -r > /tmp/bandwidth.log

# Parse raw output
cat /tmp/bandwidth.log | cut -d: -f2 | sort | uniq -c | sort -rn
```

### Compare Interface Traffic

```bash
# Monitor WiFi
sudo bandwhich -i en0

# Monitor Ethernet (separate terminal)
sudo bandwhich -i en1
```

### Identify Unexpected Connections

```bash
# Raw mode shows all connections
sudo bandwhich -r -n | grep -v "127.0.0.1" | head -20
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick bandwidth check | `sudo bandwhich -n` (no DNS delay) |
| Machine-readable output | `sudo bandwhich -r` |
| Specific interface | `sudo bandwhich -i <iface> -n` |
| Capture sample | `sudo timeout 5 bandwhich -r > /tmp/bw.log` |
| Parse top processes | `sudo bandwhich -r \| cut -d: -f2 \| sort \| uniq -c` |

## Quick Reference

### bandwhich Flags

| Flag | Long | Description |
|------|------|-------------|
| `-i` | `--interface` | Monitor specific network interface |
| `-r` | `--raw` | Machine-readable output (no TUI) |
| `-n` | `--no-resolve` | Skip DNS resolution (faster) |
| `-h` | `--help` | Show help |
| `-V` | `--version` | Show version |

### Raw Output Format

```
<interface>:<process_name>:<bytes_downloaded>:<bytes_uploaded>
```

Example:
```
en0:firefox:1048576:65536
en0:curl:4096:1024
```

## Installation

### bandwhich

```bash
# macOS
brew install bandwhich

# Cargo
cargo install bandwhich

# Linux (grant capabilities to avoid sudo)
sudo setcap cap_net_raw,cap_net_admin+ep $(which bandwhich)
```

### Sniffnet

```bash
# macOS
brew install sniffnet

# Cargo
cargo install sniffnet

# GitHub releases (pre-built binaries)
# https://github.com/GyulyVGC/sniffnet/releases
```

## Troubleshooting

### Permission Denied

```bash
# Use sudo
sudo bandwhich

# Or set capabilities (Linux)
sudo setcap cap_net_raw,cap_net_admin+ep $(which bandwhich)

# Verify capabilities
getcap $(which bandwhich)
```

### Interface Not Found

```bash
# List available interfaces
ip link show        # Linux
networksetup -listallhardwareports  # macOS
ifconfig -l         # BSD/macOS

# Then specify
sudo bandwhich -i <interface_name>
```

### DNS Resolution Slow

```bash
# Disable DNS lookup
sudo bandwhich -n
```

## Resources

- **bandwhich**: https://github.com/imsnif/bandwhich
- **Sniffnet**: https://github.com/GyulyVGC/sniffnet
- **Sniffnet Wiki**: https://github.com/GyulyVGC/sniffnet/wiki
