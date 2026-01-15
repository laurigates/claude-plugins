---
name: DNS Tools
description: Modern DNS query tools with focus on dog for readable, colorized output and modern protocol support (DoT/DoH).
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
---

# DNS Tools

## Core Expertise

**dog** is a modern, Rust-based DNS client that serves as a user-friendly alternative to `dig`. Key advantages:

- **Readable output**: Colorized, human-friendly formatting by default
- **Modern protocols**: Native support for DNS-over-TLS (DoT) and DNS-over-HTTPS (DoH)
- **JSON output**: Machine-parseable output for scripting and automation
- **Fast**: Compiled Rust binary with minimal dependencies
- **Cross-platform**: Works on Linux, macOS, and Windows

### Installation

```bash
# macOS
brew install dog

# Cargo (any platform)
cargo install dog

# Arch Linux
pacman -S dog
```

## Essential Commands

### Basic Queries

```bash
# Query A record (default)
dog example.com

# Query specific record type
dog example.com MX
dog example.com AAAA
dog example.com TXT

# Query multiple record types
dog example.com A AAAA MX

# Query multiple domains
dog example.com example.org
```

### Specifying DNS Server

```bash
# Use specific resolver
dog @8.8.8.8 example.com
dog @1.1.1.1 example.com MX

# Use system resolver explicitly
dog @/etc/resolv.conf example.com
```

### Output Formats

```bash
# JSON output for parsing
dog --json example.com

# Short output (answers only)
dog --short example.com

# Quiet mode (minimal output)
dog -q example.com
```

## DNS-over-TLS and DNS-over-HTTPS

Modern encrypted DNS protocols prevent eavesdropping and tampering.

### DNS-over-TLS (DoT)

```bash
# Query via DoT (port 853)
dog --tls @dns.google example.com
dog --tls @1.1.1.1 example.com

# Explicit TLS server specification
dog --tls @dns.quad9.net example.com
```

### DNS-over-HTTPS (DoH)

```bash
# Query via DoH
dog --https @https://dns.google/dns-query example.com
dog --https @https://cloudflare-dns.com/dns-query example.com

# Quad9 DoH
dog --https @https://dns.quad9.net/dns-query example.com
```

### Protocol Comparison

| Protocol | Flag | Port | Use Case |
|----------|------|------|----------|
| UDP | (default) | 53 | Standard queries |
| TCP | `--tcp` | 53 | Large responses, reliability |
| DoT | `--tls` | 853 | Encrypted, TLS-based |
| DoH | `--https` | 443 | Encrypted, HTTPS-based |

## Advanced Features

### Query Options

```bash
# Force TCP instead of UDP
dog --tcp example.com

# Set query timeout (seconds)
dog --timeout 5 example.com

# Disable recursion (query authoritative only)
dog --no-recurse example.com

# Query specific class
dog --class CH version.bind TXT  # Chaos class for version info
```

### Reverse DNS

```bash
# PTR lookup for IP address
dog -x 8.8.8.8
dog --reverse 1.1.1.1
```

### DNSSEC Queries

```bash
# Request DNSSEC records
dog --dnssec example.com

# Query DNSKEY records directly
dog example.com DNSKEY
dog example.com DS
```

## Common Patterns

### Troubleshooting DNS

```bash
# Check propagation across multiple resolvers
dog @8.8.8.8 example.com A
dog @1.1.1.1 example.com A
dog @9.9.9.9 example.com A

# Verify MX records for email
dog example.com MX --json | jq '.answers[].data'

# Check SPF/DKIM/DMARC for email auth
dog example.com TXT | grep -E 'spf|dkim|dmarc'
dog _dmarc.example.com TXT
dog selector._domainkey.example.com TXT
```

### Automation and Scripting

```bash
# Extract IP addresses from JSON
dog --json example.com A | jq -r '.answers[].data'

# Check if domain resolves
dog --short example.com && echo "Resolves" || echo "No resolution"

# Batch queries
for domain in example.com example.org; do
  dog --json "$domain" A
done
```

## Alternative Tools

### dig (Traditional)

Still valuable for DNSSEC validation and advanced debugging:

```bash
# DNSSEC validation
dig +dnssec example.com

# Trace delegation path
dig +trace example.com

# Query with specific options
dig +noall +answer example.com MX
```

### drill (LDNS Project)

DNSSEC-focused tool from NLnet Labs:

```bash
# DNSSEC chase
drill -S example.com

# Trace from root
drill -T example.com
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Parse results | `dog --json example.com` |
| Quick check | `dog --short example.com` |
| Minimal output | `dog -q example.com A` |
| Extract IPs | `dog --json example.com A \| jq -r '.answers[].data'` |
| Batch queries | Loop with `--json` for structured output |
| CI/CD checks | `dog --json --timeout 5` for fast, parseable results |

## Quick Reference

### Record Types

| Type | Description | Example |
|------|-------------|---------|
| A | IPv4 address | `dog example.com A` |
| AAAA | IPv6 address | `dog example.com AAAA` |
| MX | Mail exchanger | `dog example.com MX` |
| NS | Name server | `dog example.com NS` |
| TXT | Text record | `dog example.com TXT` |
| CNAME | Canonical name | `dog www.example.com CNAME` |
| SOA | Start of authority | `dog example.com SOA` |
| PTR | Pointer (reverse) | `dog -x 8.8.8.8` |
| SRV | Service record | `dog _sip._tcp.example.com SRV` |
| CAA | Certificate authority | `dog example.com CAA` |

### Common Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--json` | `-J` | JSON output |
| `--short` | `-s` | Answers only |
| `--tcp` | `-T` | Use TCP |
| `--tls` | | DNS-over-TLS |
| `--https` | `-H` | DNS-over-HTTPS |
| `--reverse` | `-x` | Reverse lookup |
| `--timeout` | | Query timeout |
| `--dnssec` | `-D` | Request DNSSEC |
| `--class` | `-C` | Query class |
| `--no-recurse` | | Disable recursion |

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| NXDOMAIN | Domain does not exist | Verify domain spelling |
| SERVFAIL | Server failure | Try different resolver |
| REFUSED | Query refused | Server policy, try public resolver |
| Timeout | No response | Check network, increase `--timeout` |
| Connection refused | DoT/DoH server unreachable | Verify server address and port |
