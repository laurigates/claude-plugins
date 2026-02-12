---
model: haiku
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
name: network-diagnostics
description: Connectivity troubleshooting with modern Rust-based tools - trippy (traceroute/mtr), gping (graphical ping), and ss (socket statistics). Preferred over legacy netstat/traceroute.
allowed-tools: Bash(ping *), Bash(traceroute *), Bash(mtr *), Bash(netstat *), Bash(ss *), Bash(ip *), Read, Grep, Glob, TodoWrite
---

# Network Diagnostics

Expert knowledge for network connectivity troubleshooting using modern diagnostic tools that provide richer output than legacy alternatives.

## Core Expertise

### Tool Selection

| Use Case | Tool | Why |
|----------|------|-----|
| Path analysis with latency | trippy | Combines traceroute + ping with TUI |
| Multi-host latency comparison | gping | Visual graphs, parallel pings |
| Local socket inspection | ss | Modern netstat replacement |
| Quick single-hop latency | gping | Faster feedback than trippy |
| Network path + ASN info | trippy | Built-in ASN/geo lookups |

### Advantages Over Legacy Tools

| Modern | Legacy | Improvements |
|--------|--------|--------------|
| trippy | traceroute, mtr | TUI, jitter stats, ASN/geo, world map |
| gping | ping | Visual graphs, multi-host parallel |
| ss | netstat | Faster, more info, better filtering |

## Trippy - Modern Traceroute/MTR

Rust-based network path analyzer combining traceroute and ping with a rich TUI.

### Essential Commands

```bash
# Basic traceroute with TUI
trip example.com

# Specify protocol mode
trip -m icmp example.com    # ICMP (default, needs root/caps)
trip -m udp example.com     # UDP (no root needed)
trip -m tcp example.com     # TCP

# TCP to specific port
trip -m tcp -p 443 example.com
trip -m tcp -p 80 example.com

# Specify source interface
trip -i en0 example.com
trip -i eth0 example.com

# Enable ASN lookups in TUI
trip --tui-as-mode asn example.com
trip --tui-as-mode prefix example.com

# Geo-location in TUI
trip --tui-geoip-mode short example.com
trip --tui-geoip-mode long example.com
```

### Non-Interactive Output

```bash
# JSON output for parsing
trip example.com --mode json -c 10

# Dot format (Graphviz)
trip example.com --mode dot -c 10

# CSV format
trip example.com --mode csv -c 10

# Flows (path changes)
trip example.com --mode flows -c 10

# Silent mode (summary only)
trip example.com --mode silent -c 10

# Pretty print (no TUI)
trip example.com --mode pretty -c 10
```

### Advanced Options

```bash
# Set packet count
trip example.com -c 100

# Set max TTL (hops)
trip example.com -t 30

# Set packet size
trip example.com -S 64

# First TTL to start from
trip example.com -f 5

# Parallel probes per hop
trip example.com -N 16

# Grace period after target reached
trip example.com -g 100ms
```

## gping - Graphical Ping

Visual latency graphs with multi-host parallel ping support.

### Essential Commands

```bash
# Basic ping with graph
gping example.com

# Multiple hosts (parallel comparison)
gping google.com cloudflare.com amazon.com

# Force IPv4/IPv6
gping -4 example.com
gping -6 example.com

# Specify interface
gping -i en0 example.com

# Simple graphics (ASCII, for terminals without unicode)
gping -s example.com

# Set buffer size (number of pings to display)
gping -b 100 example.com
```

### Command Execution Mode

```bash
# Ping a command's execution time instead of host
gping --cmd "curl -s https://api.example.com/health"
gping --cmd "dig example.com"
gping --cmd "http https://api.example.com/status"

# Compare multiple commands
gping --cmd "curl -s localhost:3000" --cmd "curl -s localhost:8080"
```

### Customization

```bash
# Set ping interval (seconds)
gping -n 0.5 example.com

# Watch specific timeout
gping -w 2 example.com

# Clear screen before starting
gping --clear example.com
```

## ss - Socket Statistics

Modern replacement for netstat, faster and more informative.

### Essential Commands

```bash
# All TCP connections
ss -t

# All UDP sockets
ss -u

# Listening sockets only
ss -l

# Show process info (requires root for other users' processes)
ss -p

# Numeric output (no DNS resolution)
ss -n

# Combined: listening TCP with process info, numeric
ss -tlnp

# Combined: all TCP/UDP listening sockets with processes
ss -tulnp
```

### Filtering

```bash
# Filter by state
ss -t state established
ss -t state listening
ss -t state time-wait
ss -t state close-wait

# Filter by port
ss -t sport = :22
ss -t dport = :443
ss -t 'sport = :80 or dport = :80'

# Filter by address
ss -t src 192.168.1.0/24
ss -t dst 10.0.0.1

# Combined filters
ss -t 'sport = :443 and dst 10.0.0.0/8'
```

### Statistics and Summary

```bash
# Socket summary statistics
ss -s

# Extended info (memory, congestion)
ss -e

# Timer info (retransmits, keepalives)
ss -o

# Memory usage
ss -m

# Full detail
ss -i
```

### Common Investigations

```bash
# Find what's using a port
ss -tlnp | grep :8080
ss -tlnp 'sport = :8080'

# Count connections by state
ss -t state established | wc -l

# Find connections to specific host
ss -tn dst 192.168.1.100

# Monitor established connections to a service
watch -n 1 'ss -tn state established dport = :443 | wc -l'
```

## Common Patterns

### Connectivity Troubleshooting Workflow

```bash
# Step 1: Check if host responds
gping target.example.com

# Step 2: Analyze network path
trip target.example.com

# Step 3: Check local listening services
ss -tlnp

# Step 4: Verify outbound connectivity
ss -tn state established | grep target.example.com
```

### Latency Comparison

```bash
# Compare multiple endpoints
gping primary.example.com secondary.example.com backup.example.com

# Compare DNS providers
gping 8.8.8.8 1.1.1.1 9.9.9.9

# Compare API endpoints
gping --cmd "curl -s api1.example.com" --cmd "curl -s api2.example.com"
```

### Port Availability Check

```bash
# What's listening on common ports
ss -tlnp 'sport = :80 or sport = :443 or sport = :8080 or sport = :3000'

# Find all listening ports in a range
ss -tlnp 'sport >= :8000 and sport <= :9000'
```

### Network Path Analysis

```bash
# Compare paths to different regions
trip us-east.example.com &
trip eu-west.example.com &
trip ap-southeast.example.com

# Analyze with ASN information
trip --tui-as-mode asn cdn.example.com
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick latency check | `gping -b 10 HOST 2>&1 \| head -20` |
| Path analysis (JSON) | `trip HOST --mode json -c 5` |
| Listening ports | `ss -tlnp` |
| Connection count | `ss -tn state established \| wc -l` |
| Port in use | `ss -tlnp 'sport = :PORT'` |
| Multi-host compare | `gping HOST1 HOST2 HOST3 -b 5` |
| TCP path check | `trip -m tcp -p 443 HOST --mode pretty -c 3` |

## Quick Reference

### Trippy Flags

| Flag | Long | Description |
|------|------|-------------|
| `-m` | `--mode` | Protocol: icmp, udp, tcp |
| `-p` | `--port` | Target port (tcp/udp mode) |
| `-i` | `--interface` | Source interface |
| `-c` | `--count` | Number of probes |
| `-t` | `--max-ttl` | Maximum TTL/hops |
| `-f` | `--first-ttl` | Starting TTL |
| `-S` | `--packet-size` | Packet size in bytes |
| | `--tui-as-mode` | ASN display: asn, prefix |
| | `--tui-geoip-mode` | Geo display: short, long |
| | `--mode` | Output: tui, json, csv, dot, flows, silent, pretty |

### gping Flags

| Flag | Long | Description |
|------|------|-------------|
| `-4` | | Force IPv4 |
| `-6` | | Force IPv6 |
| `-i` | `--interface` | Source interface |
| `-s` | `--simple-graphics` | ASCII-only output |
| `-b` | `--buffer` | Number of pings to display |
| `-n` | `--interval` | Ping interval (seconds) |
| `-w` | `--watch-interval` | Watch timeout |
| | `--cmd` | Ping command execution time |
| | `--clear` | Clear screen before starting |

### ss Flags

| Flag | Description |
|------|-------------|
| `-t` | TCP sockets |
| `-u` | UDP sockets |
| `-l` | Listening only |
| `-a` | All sockets |
| `-p` | Show process |
| `-n` | Numeric (no DNS) |
| `-e` | Extended info |
| `-o` | Timer info |
| `-m` | Memory usage |
| `-i` | Internal TCP info |
| `-s` | Summary statistics |

### ss State Filters

| State | Description |
|-------|-------------|
| `established` | Active connections |
| `listening` | Listening sockets |
| `time-wait` | Waiting for timeout |
| `close-wait` | Waiting for local close |
| `syn-sent` | Connection initiating |
| `syn-recv` | Connection received |

## Installation

```bash
# macOS
brew install trippy gping

# ss is part of iproute2 on Linux (usually pre-installed)
# On macOS, use netstat instead (ss not available)

# Cargo (cross-platform)
cargo install trippy
cargo install gping

# Verify installations
trip --version
gping --version
ss --version  # Linux only
```

## Platform Notes

- **trippy**: ICMP mode requires root or `CAP_NET_RAW` capability; UDP/TCP modes work without elevation
- **gping**: Works without elevation on all platforms
- **ss**: Linux only; use `netstat -an` on macOS for similar functionality

## Resources

- **Trippy**: https://trippy.cli.rs/ | https://github.com/fujiapple852/trippy
- **gping**: https://github.com/orf/gping
- **ss man page**: https://man7.org/linux/man-pages/man8/ss.8.html
