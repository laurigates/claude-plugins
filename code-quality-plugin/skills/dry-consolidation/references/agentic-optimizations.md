# DRY Consolidation — Agentic Optimizations

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Deterministic clone scan | `npx jscpd --reporters json --min-tokens 50 --output /tmp/jscpd-dry --silent <path>` then parse `duplicates[]` for exact ranges |
| Structural shape confirm | `ast-grep -p '<pattern with $METAVARS>' --lang <lang> <path>` |
| Quick scan | Use `--dry-run` to see duplication report without changes |
| Focused extraction | Use `--scope utilities` to extract only utility functions |
| Large codebase | Scope to specific directory: `/code:dry-consolidation src/components/` |
| Post-extraction verify | `npx tsc --noEmit 2>&1 | head -30` for quick type error check |
| Test run (fast) | `npm test -- --bail=1 --reporter=dot` for quick pass/fail |
