---
model: haiku
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
name: Layer 2 Network Discovery
description: Layer 2 network topology mapping and neighbor discovery using LLDP/CDP protocols and ARP scanning. Covers lldpd/lldpcli for switch topology, arp-scan-rs for fast host discovery, and arping for single-host probes.
allowed-tools: Bash(arp *), Bash(ip *), Bash(bridge *), Bash(ethtool *), Read, Write, Edit, Grep, Glob
---

# Layer 2 Network Discovery

Expert knowledge for Layer 2 network topology discovery and neighbor detection, operating below the IP layer for direct link-level visibility.

## Core Expertise

### Layer 2 vs Layer 3 Discovery

| Layer | Protocol | Information | Use Case |
|-------|----------|-------------|----------|
| L2 | LLDP/CDP | Switch ports, VLANs, neighbors | Topology mapping |
| L2 | ARP | MAC-to-IP mappings | Local host discovery |
| L3 | ICMP/TCP | IP reachability, ports | Remote host scanning |

**Why L2 matters:**
- Operates without IP routing - works on isolated networks
- Reveals physical topology (which port connects where)
- Identifies network equipment (switches, routers, phones)
- No firewall interference - L2 frames aren't filtered like IP packets

## LLDP/CDP Topology Discovery

### lldpd Overview

`lldpd` is an IEEE 802.1AB (LLDP) implementation that also supports:
- **CDP** - Cisco Discovery Protocol
- **EDP** - Extreme Discovery Protocol
- **FDP** - Foundry Discovery Protocol
- **SONMP** - SynOptics Network Management Protocol

**Architecture:**
- `lldpd` - Daemon that sends/receives LLDP frames
- `lldpcli` - CLI to query daemon and configure settings

### Installation

```bash
# Debian/Ubuntu
sudo apt install lldpd

# macOS (for development/testing)
brew install lldpd

# Start daemon
sudo systemctl enable --now lldpd
```

### Essential lldpcli Commands

```bash
# Show discovered neighbors (most common)
lldpcli show neighbors

# Detailed neighbor info with all TLVs
lldpcli show neighbors details

# Show local chassis information
lldpcli show chassis

# Show interface statistics
lldpcli show statistics

# Show all interfaces lldpd is monitoring
lldpcli show interfaces

# Show running configuration
lldpcli show configuration
```

### Neighbor Output Interpretation

```
-------------------------------------------------------------------------------
LLDP neighbors:
-------------------------------------------------------------------------------
Interface:    eth0, via: LLDP, RID: 1, Time: 0 day, 00:05:32
  Chassis:
    ChassisID:    mac 00:1a:2b:3c:4d:5e
    SysName:      switch-core-01
    SysDescr:     Cisco IOS Software, C3750 Software
    MgmtIP:       10.0.0.1
    Capability:   Bridge, on
    Capability:   Router, off
  Port:
    PortID:       ifname GigabitEthernet0/1
    PortDescr:    Server Room Rack A
    TTL:          120
  VLAN:        100, pvid: yes
```

**Key fields:**
- **ChassisID** - Unique switch identifier (usually MAC)
- **SysName** - Switch hostname
- **PortID/PortDescr** - Which port you're connected to
- **VLAN** - VLAN assignment on that port

### Configuration

```bash
# Enable CDP reception (for Cisco environments)
lldpcli configure lldp portidsubtype ifname
lldpcli configure cdp status rx-only

# Set system description
lldpcli configure system description "Application Server"

# Set interface description
lldpcli configure ports eth0 lldp portdescription "Primary uplink"

# Disable LLDP on specific interface
lldpcli configure ports eth1 lldp status disabled
```

Configuration file: `/etc/lldpd.conf` or `/etc/lldpd.d/*.conf`

```
# /etc/lldpd.conf
configure system description "Production Web Server"
configure lldp portidsubtype ifname
configure cdp status rx-only
```

## ARP Scanning for Host Discovery

### arp-scan-rs

Fast, Rust-based ARP scanner for local network host discovery.

```bash
# Install
cargo install arp-scan

# Basic scan (default interface)
arp-scan -l

# Specify interface
arp-scan -i en0 -l

# Scan specific subnet
arp-scan -i eth0 192.168.1.0/24

# Fast profile (less accuracy, more speed)
arp-scan -p fast -l

# Stealth profile (slower, harder to detect)
arp-scan -p stealth -l

# JSON output for parsing
arp-scan -l --json

# Show only responding hosts
arp-scan -l --alive-only
```

### Scan Profiles

| Profile | Timing | Retries | Use Case |
|---------|--------|---------|----------|
| `default` | Balanced | 2 | General use |
| `fast` | Aggressive | 1 | Quick enumeration |
| `stealth` | Slow | 1 | Minimize detection |

### Output Parsing

```bash
# Get IPs only
arp-scan -l --json | jq -r '.hosts[].ip'

# Get MAC addresses
arp-scan -l --json | jq -r '.hosts[] | "\(.ip) \(.mac)"'

# Count discovered hosts
arp-scan -l --json | jq '.hosts | length'
```

### arping - Single Host Probe

`arping` sends ARP requests to a specific host - useful for:
- Checking if host is alive at L2 when ICMP is blocked
- Detecting IP conflicts (multiple responses)
- Waking hosts from sleep states

```bash
# Basic ARP ping
arping 192.168.1.1

# Specify source interface
arping -I eth0 192.168.1.1

# Count of requests
arping -c 3 192.168.1.1

# Timeout in seconds
arping -w 5 192.168.1.1

# Duplicate address detection mode
arping -D 192.168.1.100
```

## Common Patterns

### Discover Network Topology

```bash
# 1. Find all hosts on local segment
arp-scan -l --json > /tmp/hosts.json

# 2. Check LLDP neighbors for switch info
lldpcli show neighbors

# 3. Correlate: which switch port serves which host
lldpcli show neighbors | grep -A 10 "Interface:"
```

### Identify Unknown Devices

```bash
# Get MAC vendor info (arp-scan-rs includes OUI database)
arp-scan -l

# Sample output includes vendor:
# 192.168.1.50    00:11:32:xx:xx:xx    Synology Inc.
# 192.168.1.51    dc:a6:32:xx:xx:xx    Raspberry Pi
```

### Check Physical Port Assignment

```bash
# On the server, see which switch port you're connected to
lldpcli show neighbors | grep -E "(Interface|PortID|PortDescr)"
```

### Monitor for New Neighbors

```bash
# Watch for LLDP changes
watch -n 30 'lldpcli show neighbors'

# Log neighbor events
journalctl -u lldpd -f
```

### Scripted Topology Export

```bash
# Export neighbors as JSON (requires lldpd 1.0+)
lldpcli show neighbors -f json

# Parse with jq
lldpcli show neighbors -f json | jq '.lldp.interface[] | {
  local_if: .name,
  remote_chassis: .chassis[].name[].value,
  remote_port: .port[].id[].value
}'
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick host list | `arp-scan -l --json \| jq -r '.hosts[].ip'` |
| Count hosts | `arp-scan -l --json \| jq '.hosts \| length'` |
| Fast scan | `arp-scan -p fast -l --alive-only` |
| LLDP neighbors JSON | `lldpcli show neighbors -f json` |
| Switch port info | `lldpcli show neighbors \| grep -E "(PortID\|PortDescr)"` |
| Single host check | `arping -c 1 -w 1 192.168.1.1; echo $?` |

## Quick Reference

### arp-scan-rs Flags

| Flag | Long | Description |
|------|------|-------------|
| `-l` | `--localnet` | Scan local network |
| `-i` | `--interface` | Specify interface |
| `-p` | `--profile` | Scan profile (default/fast/stealth) |
| | `--json` | JSON output |
| | `--alive-only` | Only show responding hosts |

### lldpcli Commands

| Command | Description |
|---------|-------------|
| `show neighbors` | List discovered neighbors |
| `show neighbors details` | Full TLV information |
| `show chassis` | Local system info |
| `show statistics` | Frame counters |
| `show interfaces` | Monitored interfaces |
| `show configuration` | Running config |

### arping Flags

| Flag | Description |
|------|-------------|
| `-I` | Source interface |
| `-c` | Number of requests |
| `-w` | Timeout in seconds |
| `-D` | Duplicate address detection |
| `-q` | Quiet mode |

## Troubleshooting

### lldpd Not Receiving Neighbors

```bash
# Check daemon is running
systemctl status lldpd

# Verify interface is being monitored
lldpcli show interfaces

# Check for blocked frames (some switches filter LLDP)
tcpdump -i eth0 ether proto 0x88cc

# Ensure interface is up
ip link show eth0
```

### arp-scan Permission Denied

```bash
# ARP scanning requires raw socket access
sudo arp-scan -l

# Or grant capability
sudo setcap cap_net_raw+ep $(which arp-scan)
```

### No ARP Responses

```bash
# Verify you're on the same L2 segment
ip route get 192.168.1.1

# Check for ARP blocking (rare)
ip neigh show

# Try arping for single-host debugging
arping -c 3 192.168.1.1
```

## Requirements

```bash
# Debian/Ubuntu
sudo apt install lldpd arping

# macOS
brew install lldpd arping

# arp-scan-rs (all platforms)
cargo install arp-scan
```
