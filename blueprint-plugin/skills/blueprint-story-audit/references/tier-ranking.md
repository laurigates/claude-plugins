# story-audit — Step 4 Default Tier Ranking

| Tier | Combination | Examples |
|------|-------------|----------|
| 1 — **critical untested** | core capability × zero tests | state machines, auth, payment paths |
| 2 — **partial coverage** | core capability × `~` confidence tests only | UI flows tested only at the unit level |
| 3 — **declared drift** | `❌ missing` PRD story | OCR named in PRD, never implemented |
| 4 — **implicit candidates** | `🆕 candidate` from Step 2 | code-only features awaiting story promotion |
| 5 — **healthy** | `✅` with `✓` tests | reference for "what good looks like" |
