---
model: opus
name: dual-write
description: |
  Dual write (double write) migration pattern for safely transitioning between data stores.
  Use when planning or implementing database migrations, switching storage backends, migrating
  to new schemas, or reviewing code that writes to multiple systems simultaneously.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, TodoWrite
created: 2026-02-18
modified: 2026-02-18
reviewed: 2026-02-18
---

# Dual Write Migration Pattern

Dual write keeps two data stores in sync by writing to both the old and new system on every mutation. This enables gradual migration with rollback safety.

## When to Use This Skill

| Use this skill when... | Use shadow-mode instead when... |
|------------------------|--------------------------------|
| Migrating between databases or schemas | Validating read-path behavior under real traffic |
| Switching storage backends (SQL to NoSQL, etc.) | Testing a new service without writing to it |
| Need both systems to stay authoritative during transition | Only need to compare responses, not persist data |
| Planning zero-downtime data migrations | Mirroring traffic to a staging environment |
| Reviewing code that writes to multiple data stores | Evaluating performance of a replacement system |

## Core Concepts

### Migration Phases

| Phase | Primary reads | Primary writes | Secondary writes | Duration |
|-------|--------------|----------------|------------------|----------|
| 1. Prepare | Old | Old | None | Setup |
| 2. Dual write | Old | Old + New | New (async or sync) | Migration window |
| 3. Backfill | Old | Old + New | New | Until parity |
| 4. Shadow read | Old + New (compare) | Old + New | New | Validation |
| 5. Cutover | New | New | Old (optional) | Transition |
| 6. Cleanup | New | New | None | Final |

### Write Strategies

| Strategy | Consistency | Latency impact | Failure mode |
|----------|------------|----------------|--------------|
| Synchronous | Strong | Higher (2x write) | Fail if either store fails |
| Async secondary | Eventual | Minimal | Secondary may lag |
| Outbox pattern | Eventual | Minimal | Requires message broker |
| Change data capture | Eventual | None (DB-level) | Requires CDC infrastructure |

## Implementation Architecture

### Synchronous Dual Write

```
Client Request
    │
    ▼
┌─────────────┐
│  Application │
│    Layer     │
└──────┬──────┘
       │ write(data)
       ▼
┌─────────────┐
│  Dual Write  │
│  Adapter     │
├──────┬──────┤
│      │      │
▼      │      ▼
Old DB │   New DB
       │
   Compare on
   read (optional)
```

### Key Components

| Component | Responsibility |
|-----------|---------------|
| Write adapter | Routes writes to both stores, handles failures |
| Read comparator | Reads from both, logs discrepancies, returns primary |
| Backfill job | Copies historical data from old to new store |
| Reconciliation | Detects and resolves drift between stores |
| Feature flags | Controls which phase is active per entity/tenant |

## Implementation Patterns

### Write Adapter Pattern

The write adapter wraps both stores behind a single interface:

1. Accept the write request
2. Write to the primary (old) store first
3. Write to the secondary (new) store
4. If secondary fails: log the failure, enqueue for retry, do not fail the request
5. Return the primary store's result to the caller

### Read Comparison Pattern

During the shadow read phase:

1. Read from the primary (old) store — this is the authoritative response
2. Read from the secondary (new) store asynchronously
3. Compare results field by field
4. Log discrepancies with context (entity ID, field, old value, new value)
5. Return the primary store's result
6. Track comparison metrics (match rate, common divergence fields)

### Backfill Strategy

1. Snapshot the old store at a known point in time
2. Begin dual writes for all new mutations
3. Copy historical records in batches (oldest first or by priority)
4. Track backfill progress per entity type
5. Reconcile records modified during backfill (dual write wins over backfill)

## Failure Handling

| Failure scenario | Response | Recovery |
|-----------------|----------|----------|
| Secondary write fails | Log, continue, enqueue retry | Async retry with backoff |
| Primary write fails | Fail the request (do not write to secondary) | Standard error handling |
| Both fail | Fail the request | Standard error handling |
| Secondary write timeout | Log, continue | Async verification and repair |
| Inconsistency detected | Log with full context | Manual or automated reconciliation |

### Consistency Guarantees

- Primary store is always the source of truth until cutover
- Secondary store may lag during async dual write
- Reconciliation jobs detect and repair drift
- Cutover only happens when match rate reaches threshold (e.g., 99.9%)

## Cutover Decision Criteria

| Metric | Threshold | How to measure |
|--------|-----------|----------------|
| Read comparison match rate | > 99.9% | Shadow read comparison logs |
| Backfill completion | 100% | Backfill progress tracker |
| Secondary write success rate | > 99.95% | Write adapter metrics |
| P99 latency impact | < 20% increase | Application metrics |
| Reconciliation gap | 0 unresolved | Reconciliation job output |

## Common Pitfalls

| Pitfall | Mitigation |
|---------|-----------|
| Ordering issues between stores | Use idempotent writes, include version/timestamp |
| Transaction boundaries differ | Design writes to be independently valid |
| Schema mismatch between stores | Map fields explicitly, handle nullability differences |
| Backfill conflicts with live writes | Live dual writes take precedence over backfill |
| Performance degradation | Start with async secondary writes |
| Partial failures leave inconsistency | Reconciliation job as safety net |
| Forgetting to dual-write in all code paths | Centralize through write adapter, audit call sites |

## Rollback Plan

| Phase | Rollback action | Data impact |
|-------|----------------|-------------|
| Dual write | Stop writing to new store | No data loss |
| Shadow read | Stop comparing reads | No data loss |
| Cutover (reads) | Switch reads back to old | No data loss if still dual-writing |
| Cutover (writes) | Reverse write order | May need reconciliation |
| Cleanup | Cannot rollback | Old store decommissioned |

## Monitoring Checklist

- [ ] Write success rate per store
- [ ] Write latency per store (P50, P95, P99)
- [ ] Read comparison match rate
- [ ] Backfill progress percentage
- [ ] Reconciliation queue depth
- [ ] Error rate by failure type
- [ ] Feature flag state per tenant/entity

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Code review | Check that all write paths go through the dual-write adapter |
| Architecture review | Verify failure handling, rollback plan, and cutover criteria |
| Implementation | Start with write adapter + async secondary, add comparison later |
| Testing | Simulate secondary failures, verify primary is unaffected |

## Quick Reference

| Term | Definition |
|------|-----------|
| Primary store | The authoritative data store (old system during migration) |
| Secondary store | The new data store being migrated to |
| Backfill | Copying historical data from primary to secondary |
| Reconciliation | Detecting and repairing differences between stores |
| Cutover | Switching the primary designation from old to new |
| Match rate | Percentage of shadow reads that return identical results |
| Write adapter | Abstraction layer that routes writes to both stores |
