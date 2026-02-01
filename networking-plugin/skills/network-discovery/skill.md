---
model: haiku
name: Network Discovery
description: Host and port discovery using RustScan for fast TCP scanning, arp-scan-rs for local network enumeration, and nmap for deep service analysis.
allowed-tools: Bash(nmap *), Bash(ping *), Bash(arp *), Bash(ip *), Read, Grep, Glob, TodoWrite
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
---

# Network Discovery

## Core Expertise

Network discovery follows a two-phase approach: **fast enumeration** followed by **deep analysis**.

### Why This Workflow

| Phase | Tool | Purpose | Time |
|-------|------|---------|------|
| Discovery | RustScan | Scan all 65,535 TCP ports | Seconds |
| Discovery | arp-scan-rs | Find hosts on local network | Sub-second |
| Analysis | nmap | Service detection, scripts | Minutes |

### RustScan Advantages

- Scans all ports in 3-8 seconds (vs nmap's minutes/hours)
- Automatically chains into nmap for service detection
- Handles ulimit and batch sizing for reliability
- Written in Rust for memory safety and speed

### arp-scan-rs Advantages

- Faster than traditional arp-scan
- Built-in scan profiles (default, fast, stealth)
- VLAN tagging support
- JSON output for parsing

## Essential Commands

### RustScan - Fast Port Discovery

```bash
# Scan single host (all 65k ports)
rustscan -a 192.168.1.100

# Scan with nmap service detection
rustscan -a 192.168.1.100 -- -sV

# Scan with nmap scripts (default safe scripts)
rustscan -a 192.168.1.100 -- -sV -sC

# Scan multiple hosts
rustscan -a 192.168.1.100,192.168.1.101

# Scan from file
rustscan -a hosts.txt

# Scan specific ports only
rustscan -a 192.168.1.100 -p 22,80,443

# Scan port range
rustscan -a 192.168.1.100 -r 1-1000

# Adjust for reliability (slower but more accurate)
rustscan -a 192.168.1.100 --ulimit 5000 --batch-size 2500
```

### arp-scan-rs - Local Network Discovery

```bash
# Scan local network (auto-detect interface)
arp-scan-rs -l

# Scan specific interface
arp-scan-rs -i en0

# Scan specific range
arp-scan-rs 192.168.1.0/24

# Fast profile (less accurate, faster)
arp-scan-rs -l --profile fast

# Stealth profile (slower, harder to detect)
arp-scan-rs -l --profile stealth

# JSON output for parsing
arp-scan-rs -l --format json

# With VLAN tagging
arp-scan-rs -l --vlan 100

# Resolve hostnames
arp-scan-rs -l --resolve
```

### nmap - Deep Service Analysis

Use nmap after RustScan identifies open ports:

```bash
# Service version detection
nmap -sV -p 22,80,443 192.168.1.100

# Service + default scripts
nmap -sV -sC -p 22,80,443 192.168.1.100

# OS fingerprinting (requires root)
sudo nmap -O -p 22,80,443 192.168.1.100

# Aggressive scan (version, scripts, OS, traceroute)
sudo nmap -A -p 22,80,443 192.168.1.100

# Vulnerability scripts
nmap --script vuln -p 80,443 192.168.1.100

# Specific service scripts
nmap --script http-* -p 80,443 192.168.1.100

# UDP scan (slower, requires root)
sudo nmap -sU -p 53,161 192.168.1.100
```

## Common Patterns

### Full Network Reconnaissance

```bash
# 1. Discover live hosts
arp-scan-rs -l --format json > hosts.json

# 2. Extract IPs and scan ports
arp-scan-rs -l | awk '{print $1}' > hosts.txt
rustscan -a hosts.txt -- -sV -oN scan-results.txt

# 3. Deep dive on specific services
nmap -sV -sC --script vuln -p 22 -iL hosts.txt
```

### Quick Web Server Discovery

```bash
# Find hosts with web servers
rustscan -a 192.168.1.0/24 -p 80,443,8080,8443 -- -sV

# Enumerate web technologies
nmap --script http-headers,http-title -p 80,443 192.168.1.100
```

### Quiet/Stealth Scanning

```bash
# Slow ARP discovery
arp-scan-rs -l --profile stealth

# RustScan with lower batch (less noisy)
rustscan -a 192.168.1.100 --batch-size 500 --ulimit 1000

# nmap timing template (T0=paranoid, T1=sneaky)
nmap -T1 -sV -p 22,80 192.168.1.100
```

### Service-Specific Deep Dives

```bash
# SSH enumeration
nmap --script ssh-* -p 22 192.168.1.100

# SMB enumeration
nmap --script smb-* -p 445 192.168.1.100

# DNS enumeration
nmap --script dns-* -p 53 192.168.1.100
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick port check | `rustscan -a $IP -p $PORTS 2>/dev/null` |
| Host discovery | `arp-scan-rs -l --format json 2>/dev/null` |
| Minimal output | `rustscan -a $IP --greppable` |
| JSON parsing | `arp-scan-rs -l --format json \| jq -r '.[].ip'` |
| Service IDs only | `nmap -sV -p $PORTS $IP -oG - \| grep open` |
| Suppress banners | `rustscan -a $IP -q -- -sV` |
| Fast local scan | `arp-scan-rs -l --profile fast --format json` |

## Quick Reference

### RustScan Flags

| Flag | Description |
|------|-------------|
| `-a` | Target address(es) or file |
| `-p` | Specific ports (comma-separated) |
| `-r` | Port range (e.g., 1-1000) |
| `--ulimit` | Max file descriptors (default: 5000) |
| `--batch-size` | Ports per batch (default: 4500) |
| `--timeout` | Timeout in ms (default: 1500) |
| `-g, --greppable` | Greppable output format |
| `-q` | Quiet mode |
| `--` | Pass remaining args to nmap |

### arp-scan-rs Flags

| Flag | Description |
|------|-------------|
| `-l` | Scan local network |
| `-i` | Interface to use |
| `--profile` | Scan profile (default/fast/stealth) |
| `--format` | Output format (plain/json) |
| `--vlan` | VLAN ID for tagging |
| `--resolve` | Resolve hostnames |
| `--timeout` | Response timeout in ms |

### nmap Common Flags

| Flag | Description |
|------|-------------|
| `-sV` | Service version detection |
| `-sC` | Default script scan |
| `-O` | OS detection (requires root) |
| `-A` | Aggressive (version + scripts + OS) |
| `-p` | Port specification |
| `-T<0-5>` | Timing template (0=slowest) |
| `-oN` | Normal output to file |
| `-oG` | Greppable output |
| `-oX` | XML output |
| `--script` | Run specific NSE scripts |
| `-iL` | Input from host list file |

### nmap Timing Templates

| Template | Name | Use Case |
|----------|------|----------|
| `-T0` | Paranoid | IDS evasion |
| `-T1` | Sneaky | IDS evasion |
| `-T2` | Polite | Less bandwidth |
| `-T3` | Normal | Default |
| `-T4` | Aggressive | Fast networks |
| `-T5` | Insane | Very fast networks |

## Error Handling

### RustScan Issues

**"Too many open files":**
```bash
# Reduce ulimit and batch size
rustscan -a $IP --ulimit 2000 --batch-size 1000
```

**Slow scans:**
```bash
# Increase batch size (if system allows)
rustscan -a $IP --batch-size 8000 --ulimit 10000
```

### arp-scan-rs Issues

**"Permission denied":**
```bash
# ARP scanning requires raw socket access
sudo arp-scan-rs -l
```

**No hosts found:**
```bash
# Verify interface
arp-scan-rs -l -i en0  # Specify correct interface
```

### nmap Issues

**"requires root":**
```bash
# OS detection and some scans need root
sudo nmap -O -p 22 $IP
```

**Slow service detection:**
```bash
# Limit version intensity
nmap -sV --version-intensity 2 -p $PORTS $IP
```
