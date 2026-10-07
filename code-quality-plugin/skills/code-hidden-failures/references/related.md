# Hidden-Failure Scanner — See Also

## See Also

- [`rules/`](../rules/) — the executable ast-grep catalog for the errors track (`sgconfig.yml` + `rules/lib/*.yml` + `rules/tests/*-test.yml`); run `ast-grep test -c rules/sgconfig.yml --skip-snapshot-tests` to verify every rule against its fixtures
- `/code:antipatterns` — delegates here for the error-swallowing category
- `/code:review` — prose code review
- `.claude/rules/shell-scripting.md` — canonical allowlist for shell `\|\| true` / `2>/dev/null`
- `REFERENCE-surfacing.md` — app-context → channel matrix and privacy rules (errors track)
- `REFERENCE-degradation.md` — the five degradation patterns, severities, and fixes (degradation track)
- `/configure:sentry`, `/configure:feature-flags` — surfacing/monitoring infrastructure
