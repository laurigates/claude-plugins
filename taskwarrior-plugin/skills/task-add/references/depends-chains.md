# task-add — Ordered Work-Order Chains

Open this when filing work orders that must land in sequence.

## Sequential WOs: use `depends:` for ordered chains

For work orders that must land in sequence (e.g., WO-058 → 059 → 060),
set `depends:` on each downstream task pointing to its predecessor's
taskwarrior numeric ID. When the predecessor closes with `task done`,
taskwarrior **automatically unblocks all dependents** — no manual
intervention needed (see `docs/task-tracking.md § Lifecycle`):

```bash
# WO-059 waits for WO-058 (taskwarrior ID 51)
task add "WO-059: ..." bpid:WO-059 +wo project:myrepo depends:51

# WO-060 waits for both
task add "WO-060: ..." bpid:WO-060 +wo project:myrepo depends:51,52
```
