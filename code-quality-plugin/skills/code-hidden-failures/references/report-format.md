# Hidden-Failure Scanner — Combined Report Format

```
Hidden-Failure Scan: <path>  (track: both)
Detected app context: <cli|frontend|backend|library|daemon|ci>

| Track       | Severity | File:Line       | Pattern                     | Recommended action               |
|-------------|----------|-----------------|-----------------------------|----------------------------------|
| errors      | High     | release.sh:42   | `npm publish ... \|\| true` | stderr + exit 1                  |
| degradation | High     | scan.ts:88      | success on zero results     | distinguish "none" vs "skipped"  |
| errors      | Medium   | api/fetch.ts:17 | empty catch                 | console.error + toast (sanitized)|

Totals: errors(high=N med=N low=N)  degradation(high=N med=N low=N)  across M files
```
