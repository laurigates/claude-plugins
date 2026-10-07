# DRY Consolidation — Output Summary Template

### Output Summary

After all phases complete, report:

```
## DRY Consolidation Summary

### Extractions
- [Abstraction Name] (type) — replaced N blocks in M files
- ...

### New Files Created
- path/to/new/file.ts — [description]
- ...

### Tests Added
- N tests across M test files

### Net Effect
- ~N lines of duplicated code consolidated
- N reusable abstractions created
- All verified: typecheck + lint + N passing tests
```
