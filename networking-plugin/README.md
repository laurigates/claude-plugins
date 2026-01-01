# networking-plugin

Modern network discovery, diagnostics, monitoring, and load testing tools - prioritizing Rust-based alternatives for performance.

## Skills

| Skill | Description |
|-------|-------------|
| [network-discovery](skills/network-discovery/skill.md) | Host and port discovery using RustScan, arp-scan-rs, and nmap |
| [network-diagnostics](skills/network-diagnostics/skill.md) | Connectivity troubleshooting with trippy, gping, and ss |
| [network-monitoring](skills/network-monitoring/skill.md) | Real-time traffic monitoring with bandwhich and Sniffnet |
| [dns-tools](skills/dns-tools/skill.md) | Modern DNS queries with dog (DoT/DoH support) |
| [layer2-discovery](skills/layer2-discovery/skill.md) | Layer 2 topology mapping with LLDP/CDP and ARP scanning |
| [http-load-testing](skills/http-load-testing/skill.md) | HTTP load testing with oha (coordinated omission handling) |

## Tool Categories

### Discovery & Scanning
| Tool | Purpose | Language |
|------|---------|----------|
| RustScan | Fast TCP port discovery (65k ports in seconds) | Rust |
| arp-scan-rs | Local network host discovery via ARP | Rust |
| nmap | Deep service detection, OS fingerprinting | C |

### Diagnostics & Troubleshooting
| Tool | Purpose | Language |
|------|---------|----------|
| trippy | Modern traceroute/mtr with TUI, ASN/geo | Rust |
| gping | Graphical ping with multi-host comparison | Rust |
| ss | Socket statistics (netstat replacement) | C |
| dog | DNS queries with DoT/DoH support | Rust |

### Monitoring & Analysis
| Tool | Purpose | Language |
|------|---------|----------|
| bandwhich | Per-process bandwidth monitoring | Rust |
| Sniffnet | GUI traffic monitor with geo-location | Rust |
| lldpd | LLDP/CDP neighbor discovery | C |

### Load Testing
| Tool | Purpose | Language |
|------|---------|----------|
| oha | HTTP load testing with latency correction | Rust |

## Installation

```bash
# Core Rust tools (via Homebrew or Cargo)
brew install rustscan trippy gping dog bandwhich oha

# Or via Cargo
cargo install rustscan trippy gping dog bandwhich oha arp-scan

# Traditional tools
brew install nmap lldpd
```

## Quick Examples

```bash
# Fast port scan → deep analysis
rustscan -a 192.168.1.100 -- -sV -sC

# Network path analysis with ASN info
trip --tui-as-mode asn example.com

# Compare latency to multiple hosts
gping 8.8.8.8 1.1.1.1 9.9.9.9

# DNS query with DoH
dog --https @https://dns.google/dns-query example.com

# Per-process bandwidth
sudo bandwhich

# HTTP load test
oha -z 30s -c 50 https://api.example.com/health
```
