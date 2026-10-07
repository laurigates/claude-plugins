---
created: 2026-07-12
modified: 2026-07-12
reviewed: 2026-07-12
name: interface-state
description: Local interface, address, route, and neighbor state with iproute2. Use when viewing or configuring a host's own IPs, links, routes, or ARP/NDP cache — the ifconfig/route/arp replacement.
user-invocable: false
allowed-tools: Bash(ip *), Bash(bridge *), Read, Grep, Glob, TodoWrite
---

# Local Interface & Routing State (iproute2)

## When to Use This Skill

| Scenario | Use this skill | Alternative |
|----------|---------------|-------------|
| Show a host's own IP addresses and interfaces | Yes (`ip -br a`) | |
| Check interface up/down state and MAC addresses | Yes (`ip -br link`) | |
| Inspect the routing table or which route a destination takes | Yes (`ip route`, `ip route get`) | |
| Read the ARP/NDP neighbor cache | Yes (`ip neigh`) | |
| See per-interface RX/TX counters, errors, drops | Yes (`ip -s link`) | |
| Script host network state as JSON | Yes (`ip -j … \| jq`) | |
| Add/remove addresses, bring links up/down, edit routes | Yes (root) | |
| Watch link/addr/route changes live | Yes (`ip monitor`) | |
| Trace the route or diagnose latency to a remote host | | network-diagnostics (trippy, gping) |
| Find what process is listening on a port | | network-diagnostics (ss) |
| Enumerate hosts on the local L2 segment | | layer2-discovery (arp-scan, LLDP) |
| Discover which switch port a host is on | | layer2-discovery (lldpcli) |
| Scan open ports on a remote host | | network-discovery (RustScan, nmap) |
| Resolve DNS records for a domain | | dns-tools (dog, dig) |
| Monitor per-process bandwidth | | network-monitoring (bandwhich) |
| Load test an HTTP endpoint | | http-load-testing (oha) |

Expert knowledge for inspecting and configuring a Linux host's **own** Layer 2/3
state — addresses, links, routes, and the neighbor cache — with the iproute2
`ip` command. This is the modern replacement for the entire `net-tools` suite:
`ifconfig`, `route`, `arp`, and `netstat -i`/`-r`.

**Platform note:** `ip` (iproute2) is **Linux-only**. On macOS the equivalents
are `ifconfig`, `netstat -rn`, `route -n get`, and `arp -a`; this skill targets
Linux hosts and the many containers/VMs/servers you shell into.

## iproute2 as the net-tools Replacement

| Legacy (net-tools) | Modern (iproute2) | Shows |
|--------------------|-------------------|-------|
| `ifconfig` | `ip addr` / `ip a` | Addresses per interface |
| `ifconfig -a` | `ip link` / `ip l` | Link state, MAC, MTU |
| `route -n` | `ip route` / `ip r` | Routing table |
| `arp -a` | `ip neigh` / `ip n` | ARP/NDP neighbor cache |
| `netstat -i` | `ip -s link` | Per-interface counters |
| `netstat -g` | `ip maddr` | Multicast group membership |
| `ifconfig eth0 up` | `ip link set eth0 up` | Bring interface up |
| `ifconfig eth0 1.2.3.4/24` | `ip addr add 1.2.3.4/24 dev eth0` | Assign address |
| `route add …` | `ip route add …` | Add a route |

`net-tools` is unmaintained and blind to modern kernel features (multiple
routing tables, policy rules, VRFs, network namespaces, IPv6 details). Prefer
`ip` on any Linux host.

## Global Flags — the Throughline

These modify **any** `ip` object and compose freely. The first three are the
core habit:

| Flag | Long form | Effect |
|------|-----------|--------|
| `-c` | `-color` | Colorize output (state/scope highlighted) |
| `-br` | `-brief` | One tidy aligned line per entry (the columnar view) |
| `-r` | `-resolve` | Reverse-DNS resolve addresses |
| `-j` | `-json` | Machine-readable JSON (pipe to `jq`) |
| `-p` | `-pretty` | Pretty-print (pair with `-j`) |
| `-s` | `-stats` | Include statistics (repeat `-s -s` for more) |
| `-4` / `-6` | | Restrict to IPv4 / IPv6 only |

```bash
# The compact colorized address table (memorable as the `ipa` shortcut)
ip -color -brief -resolve addr      # short: ip -c -br -r a

# Same treatment on other objects
ip -c -br link                      # interfaces: state + MAC, one line each
ip -c -br neigh                     # neighbor cache, columnar
ip -c route                         # colorized routing table
```

Every `ip` object accepts unambiguous abbreviations: `ip a`, `ip l`, `ip r`,
`ip n`, `ip ru` (rule), `ip m` (maddr).

## Read-Only Inspection

### Addresses & Links

```bash
ip -br a                    # addresses, one line per interface
ip -br a show up            # only interfaces that are UP (filters noise)
ip -4 -br a                 # IPv4 only
ip a show eth0              # full detail for one interface
ip -br link                 # L2 view: state, MAC, MTU — no IPs
ip link show eth0           # one interface's link details
```

### Routing

```bash
ip route                            # full routing table
ip route get 1.1.1.1                # WHICH route/interface a destination uses
ip route get 1.1.1.1 from 10.0.0.5  # source-based route selection
ip -6 route                         # IPv6 routing table
ip route show table all             # every routing table (policy routing)
```

`ip route get` answers "why is this traffic leaving the wrong interface?" — it
reports the exact route, source address, and egress device the kernel picks.

### Neighbors (ARP/NDP)

```bash
ip neigh                    # ARP (v4) + NDP (v6) cache
ip -br neigh                # columnar
ip neigh show dev eth0      # neighbors on one interface
```

Neighbor states: `REACHABLE` (confirmed), `STALE` (cached, unverified),
`DELAY`/`PROBE` (revalidating), `FAILED` (unreachable), `PERMANENT` (static).

### Statistics

```bash
ip -s link                  # RX/TX bytes, packets, errors, drops per interface
ip -s -s link show eth0     # extended error breakdown for one interface
```

First stop for "is this NIC dropping packets?" — check the `errors`/`dropped`
columns.

## JSON + jq Scripting — the Real Reason to Learn `ip`

`ip -j` emits structured JSON, so scripts parse fields reliably instead of
scraping `ifconfig` text that varies across versions.

```bash
# Pretty-printed full address dump
ip -j -p addr

# All IPv4 addresses on the host, one per line
ip -j addr | jq -r '.[].addr_info[] | select(.family=="inet") | .local'

# Primary IP of a specific interface
ip -j addr show eth0 | jq -r '.[0].addr_info[] | select(.family=="inet") | .local'

# Interfaces that are operationally UP
ip -j link | jq -r '.[] | select(.operstate=="UP") | .ifname'

# Default gateway
ip -j route | jq -r '.[] | select(.dst=="default") | .gateway'

# Neighbor cache as ip→mac pairs
ip -j neigh | jq -r '.[] | "\(.dst)\t\(.lladdr // "-")\t\(.state[0])"'
```

## Watching Changes Live

```bash
ip monitor                  # stream ALL link/addr/route/neigh changes
ip monitor link             # just interface up/down events
ip monitor address          # address add/remove (watch DHCP renewals)
ip monitor route            # routing table changes
```

`ip monitor` is invaluable for catching a flapping interface, a DHCP lease
renewal, or a VPN altering routes — it prints events as they happen.

## Modern Subsystems net-tools Never Covered

Policy rules, non-main tables, network namespaces, VLAN/bond/bridge detail, and
the `bridge` tool: see [references/advanced-subsystems.md](references/advanced-subsystems.md).

## Mutating Commands (require root)

> These change live network configuration and are **not persistent** — they
> vanish on reboot unless written into the distro's network config
> (netplan/NetworkManager/systemd-networkd). Flagged here so they're
> recognizable; run deliberately.

The add / del / set / flush / replace commands for addresses, links, routes,
and neighbors are in [references/mutating-commands.md](references/mutating-commands.md).

## Common Patterns

### What's my IP and gateway?

```bash
ip -br a show up                                  # human view
ip -j route | jq -r '.[] | select(.dst=="default") | .gateway'   # gateway only
```

### Why is traffic taking the wrong path?

```bash
ip route get <dest-ip>       # exact route + source + egress interface
ip rule                      # is a policy rule diverting it to another table?
ip route show table <n>      # inspect that table
```

### Is this interface dropping packets?

```bash
ip -s link show <dev>        # check errors / dropped counters
watch -n 1 'ip -s link show <dev> | grep -A1 RX'   # watch them climb
```

### Namespace-aware inspection (containers)

```bash
for ns in $(ip netns list | awk '{print $1}'); do
  echo "== $ns =="; ip netns exec "$ns" ip -br a
done
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Compact address table | `ip -c -br -r a` |
| Host IPv4 list | `ip -j addr \| jq -r '.[].addr_info[] \| select(.family=="inet") \| .local'` |
| Default gateway | `ip -j route \| jq -r '.[] \| select(.dst=="default") \| .gateway'` |
| Egress interface for a dest | `ip route get <ip> \| awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}'` |
| UP interfaces only | `ip -j link \| jq -r '.[] \| select(.operstate=="UP") \| .ifname'` |
| Interface error counts | `ip -s link show <dev>` |
| Neighbor ip→mac table | `ip -j neigh \| jq -r '.[] \| "\(.dst) \(.lladdr // "-")"'` |

## Quick Reference

The object and verb tables (with abbreviations) are in
[references/quick-reference.md](references/quick-reference.md).

## Troubleshooting

For `Object "a" is unknown`, `RTNETLINK answers: …` errors, and addresses that
vanish after reboot, see [references/troubleshooting.md](references/troubleshooting.md).

## Requirements

`ip` ships with iproute2 on essentially every Linux distro; install commands for
minimal images (and `jq`) are in [references/troubleshooting.md](references/troubleshooting.md).
