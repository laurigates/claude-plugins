---
name: docs-verify-machine-facts
description: Verify machine-read values (scutil, route, ifconfig, local config) against the authoritative IaC before publishing. Use when org or outward-facing docs quote DNS names, IPs, endpoints, or versions read off your own host.
allowed-tools: Read, Grep, Glob, Edit, TodoWrite
created: 2026-08-19
modified: 2026-08-19
reviewed: 2026-08-19
---

# Verify Machine-Read Facts Against the Org Source-of-Truth Before Publishing

When documenting infrastructure from values read off **your own machine**
— `ifconfig`, `scutil --dns`, `route get`, `netstat -rn`, `defaults
read`, a local config file — those readings can carry **personal or
host-specific artifacts** that are not org facts. Publishing them to
shared documentation silently passes off your home network (or a stale
local override, or another VPN) as the organization's configuration.

## The failure mode

A diagnostic session reads the live state of a tool on your laptop, the
output looks authoritative, and environment-specific lines get lifted
verbatim into an org doc:

1. You run `scutil --dns` / `route get` to investigate a VPN/tunnel.
2. The output interleaves **multiple** resolvers and routes — the org
   tunnel's *and* your home network's, your other VPN's, a local
   `/etc/hosts` override.
3. You document the interesting values without separating "this is the
   org's" from "this is mine."
4. The doc now tells every reader that the org's internal DNS domain is
   `intra.lakuz.com` with resolvers `100.95.0.251–.254` — which was the
   **author's home LAN**, not the org's anything.

The tell: the value is specific and plausible, so reviewers don't
question it — it reads as researched fact. The leak surfaces only when
someone who knows the real environment says "that's not ours."

> Canonical break (2026-06): an FVH Twingate troubleshooting DevGuide
> published `intra.lakuz.com` + `100.95.0.x` as the org's internal DNS.
> Both were the author's home network, picked up from a `scutil --dns`
> dump where the home resolver sat in `resolver #1` above the Twingate
> overlay. The real FVH resource domains (`*.dataportal.fi`, `*.fvh.io`,
> `*.cluster.local`) live in `twingate/resources.tf`. Corrected in a
> follow-up commit after the user caught it.

## The rule

Before a machine-read value lands in **org / shared / outward-facing**
documentation, cross-check it against the **authoritative source** —
not the local readout:

- **Network/DNS/routing facts** → the IaC that defines them
  (`twingate/resources.tf`, Terraform, the DHCP/DNS config), not
  `scutil`/`route`/`ifconfig` on one host.
- **Endpoints, domains, IP ranges** → the config that provisions them,
  not what resolved on your machine this session.
- **Versions, flags, paths** → the project's manifest/lockfile, not what
  happens to be installed locally.

If you cannot tie a specific value to an authoritative source, either
**omit it** or **describe the mechanism instead of the literal**. The
mechanism is environment-independent and cannot leak:

```
# Leaky — pins host-specific literals as if they were org facts
Internal DNS resolvers: 100.95.0.251–.254 ; search domain intra.lakuz.com

# Safe — verifiable mechanism, no machine-specific artifact
Twingate resolves configured resource domains (*.dataportal.fi, *.fvh.io,
*.cluster.local — see twingate/resources.tf) into the 100.96/12 overlay.
Verify by resolving the name: the answer should be a 100.96.x address.
```

## Separating yours from theirs in a multi-source readout

`scutil --dns`, `netstat -rn`, and `route get` show **all** active
resolvers/routes interleaved. To attribute a line correctly:

- A value reachable only **through the tunnel interface** (`utunN`) is
  the org's; a value on `en0`/Wi-Fi is local.
- Cross-reference the route table: the org tunnel's routes point at the
  tunnel interface and match the IaC's resource ranges. Home/local
  resolvers route via your LAN gateway.
- When in doubt, the IaC is authoritative over any local readout.

## Stale, not just misattributed

A fact true when drafted can be false when published. Re-derive mutable ones
(dates, versions, IDs, counts) in the breath that publishes. 2026-08: a draft
held through two review rounds needed a rolled-over date and 2 of 11 version
IDs fixed at post time.

## Relationship to sibling rules

- `git-plugin:git-upstream-fix-check` — same instinct (check the
  authoritative source before acting) applied to vendored code.
- `documentation-plugin:docs-single-source` — link to the source-of-truth rather than
  transcribing; a value you can't link to the source is a value you
  probably shouldn't hardcode.
- The `agent-patterns-plugin:cold-read-gate` pattern — an outside reader
  catches what the author, steeped in their own environment, cannot see is
  host-specific.

## Rationale

A wrong machine-read literal in shared docs is worse than no value: it
is confidently specific, so it propagates as fact and misleads everyone
who can't independently check it. The cost of verification is one lookup
against the IaC at authoring time; the cost of skipping it is a
published leak (sometimes of personal infrastructure) and a re-do once
someone with ground truth notices. Prefer the verifiable mechanism over
the convenient literal whenever the literal came from your own host.
