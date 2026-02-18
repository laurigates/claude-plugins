---
model: opus
name: shadow-mode
description: |
  Shadow mode (shadow traffic, dark launching) pattern for validating new systems under
  production load. Use when testing replacement services, validating new deployments,
  comparing system behavior, or planning traffic mirroring for migration validation.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, TodoWrite
created: 2026-02-18
modified: 2026-02-18
reviewed: 2026-02-18
---

# Shadow Mode Migration Pattern

Shadow mode mirrors production traffic to a new system without affecting users. The shadow system's responses are discarded — only the production response reaches the user — but both responses are logged and compared to validate correctness.

## When to Use This Skill

| Use this skill when... | Use dual-write instead when... |
|------------------------|-------------------------------|
| Validating read behavior of a replacement service | Both systems need to persist writes |
| Testing performance under real production load | You need the new store to be authoritative |
| Comparing response correctness before cutover | Migrating data stores that must stay in sync |
| Evaluating a new service version safely | The new system needs to receive and store mutations |
| Load testing a new deployment with real traffic | You need strong consistency between systems |

## Core Concepts

### Traffic Flow

```
Client Request
    │
    ▼
┌─────────────┐
│   Router /   │
│   Proxy      │
├──────┬──────┤
│      │      │
▼      │      ▼
Prod   │   Shadow
System │   System
│      │      │
▼      │      ▼
Prod   │   Shadow
Response│   Response
│      │      │
▼      │   (discard)
Client │      │
       │      ▼
       │   Compare &
       │   Log
       ▼
```

### Shadow Modes

| Mode | Description | Use case |
|------|------------|----------|
| Full mirror | 100% of traffic duplicated | Final validation before cutover |
| Sampled mirror | Percentage of traffic (e.g., 10%) | Early validation, capacity-constrained shadow |
| Selective mirror | Specific request types or endpoints | Targeted validation of changed behavior |
| Replay mirror | Recorded traffic replayed offline | Testing without live shadow infrastructure |

## Implementation Architecture

### Key Components

| Component | Responsibility |
|-----------|---------------|
| Traffic splitter | Duplicates requests to shadow system |
| Shadow router | Forwards mirrored requests, manages timeouts |
| Response comparator | Compares prod vs shadow responses |
| Discrepancy logger | Records differences with full context |
| Metrics collector | Tracks match rates, latency, error rates |
| Kill switch | Disables shadow traffic instantly if issues arise |

### Deployment Topology

| Topology | How it works | Trade-offs |
|----------|-------------|------------|
| Proxy-based | Load balancer or API gateway mirrors requests | Simple setup, adds proxy hop |
| Application-level | Application code sends async copy of request | Fine-grained control, code coupling |
| Infrastructure-level | Service mesh (Istio, Linkerd) mirrors traffic | No code changes, requires mesh |
| Log replay | Capture request logs, replay against shadow | No live infrastructure needed, not real-time |

## Implementation Patterns

### Proxy-Based Mirroring

Configure the load balancer or API gateway to:

1. Forward the original request to the production backend
2. Clone the request and send it to the shadow backend
3. Return only the production response to the client
4. Shadow response is logged but never returned
5. Shadow request timeout is independent of production

### Application-Level Mirroring

1. Intercept the incoming request at the application layer
2. Process the request normally through the production path
3. Asynchronously send a copy of the request to the shadow service
4. Do not block the production response on the shadow response
5. Compare responses in a background worker

### Response Comparison Strategy

Compare responses field by field with configurable rules:

| Field type | Comparison approach |
|-----------|-------------------|
| IDs, timestamps | Ignore (expected to differ) |
| Computed values | Compare within tolerance (e.g., floating point) |
| Collections | Compare as sets (ignore ordering unless significant) |
| Status codes | Exact match required |
| Error responses | Categorize and compare error types |
| Headers | Compare relevant headers only (Content-Type, Cache-Control) |

### Handling Stateful Requests

Shadow mode works best with read-only requests. For stateful (write) requests:

| Approach | Description |
|----------|------------|
| Skip writes | Only mirror read requests to shadow |
| Isolated state | Shadow has its own database seeded from production |
| Dry-run writes | Shadow validates the write but does not persist |
| Record-only | Log what shadow would have written, compare intent |

## Gradual Rollout

| Phase | Traffic % | Duration | Goal |
|-------|-----------|----------|------|
| 1. Smoke test | 1% | Hours | Verify shadow receives and processes requests |
| 2. Canary | 5-10% | Days | Identify obvious discrepancies |
| 3. Validation | 25-50% | Days-weeks | Build confidence in match rate |
| 4. Full mirror | 100% | Days-weeks | Final validation before cutover |

## Validation Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| Response match rate | > 99.9% | Percentage of identical responses |
| Shadow latency (P50) | Within 2x of prod | Shadow performance baseline |
| Shadow latency (P99) | Monitored | Tail latency under real load |
| Shadow error rate | < prod error rate | Shadow should not produce more errors |
| Shadow availability | Monitored | Shadow uptime (not a blocker) |
| Discrepancy categories | Trending to zero | Known differences resolved over time |

## Common Pitfalls

| Pitfall | Mitigation |
|---------|-----------|
| Shadow affects production performance | Async mirroring, independent timeouts, kill switch |
| Shadow writes to shared resources | Isolate shadow databases, queues, and external services |
| Non-deterministic responses cause false mismatches | Configure comparison rules to ignore timestamps, IDs, nonces |
| Shadow receives stale data | Seed shadow database from recent production snapshot |
| Traffic amplification overwhelms shadow | Use sampled mirroring, auto-scaling, or circuit breakers |
| Request ordering differs between prod and shadow | Compare request-by-request, not sequence-dependent |
| Authentication tokens expire for shadow | Mint shadow-specific tokens or bypass auth in shadow |

## Integration with Dual Write

Shadow mode and dual write are complementary migration techniques:

| Migration phase | Technique | Purpose |
|----------------|-----------|---------|
| Early validation | Shadow mode (reads) | Verify the new system returns correct responses |
| Data sync | Dual write | Keep both stores authoritative during transition |
| Pre-cutover | Both simultaneously | Shadow validates reads, dual write maintains data |
| Cutover | Dual write reversal | New system becomes primary, old becomes secondary |
| Post-cutover | Shadow mode (reversed) | Mirror to old system to verify nothing broke |

### Strangler Fig Context

Both patterns are tactics within the broader Strangler Fig migration strategy:

1. **Identify** a component to migrate
2. **Shadow** traffic to validate the replacement
3. **Dual write** to synchronize data stores
4. **Cut over** reads, then writes
5. **Decommission** the old component
6. Repeat for the next component

## Kill Switch Requirements

Shadow mode must have an immediate disable mechanism:

- Feature flag or configuration toggle (no deployment required)
- Disables within seconds, not minutes
- Monitored — alerts if shadow causes production impact
- Tested before enabling shadow traffic

## Monitoring Checklist

- [ ] Production latency impact (should be zero or negligible)
- [ ] Shadow request success rate
- [ ] Shadow response latency distribution
- [ ] Response match rate by endpoint
- [ ] Discrepancy log volume and categories
- [ ] Shadow system resource utilization
- [ ] Kill switch status and responsiveness

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Architecture review | Verify shadow isolation (no shared writes), kill switch exists |
| Code review | Check async mirroring does not block production path |
| Implementation | Start with proxy-based mirroring at 1%, increase gradually |
| Testing | Verify kill switch works, confirm production is unaffected when shadow fails |

## Quick Reference

| Term | Definition |
|------|-----------|
| Shadow system | The new system receiving mirrored traffic |
| Production system | The live system serving real users |
| Traffic splitter | Component that duplicates requests |
| Match rate | Percentage of shadow responses matching production |
| Kill switch | Mechanism to instantly disable shadow traffic |
| Dark launching | Synonym for shadow mode — feature is live but invisible to users |
| Canary traffic | Small percentage of mirrored requests for initial validation |
| Strangler fig | Broader migration strategy of incrementally replacing components |
