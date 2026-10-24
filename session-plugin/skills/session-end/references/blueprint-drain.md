# session-end — Blueprint Drain Wave

## Re-derive the drain wave (Step 4.3)

```sh
open=$(task '(status:pending or +ACTIVE)' export 2>/dev/null | jq -c '[.[] | .bpid // empty] | unique')
task bpid.any: status:completed export 2>/dev/null | jq -r --slurpfile t docs/blueprint/feature-tracker.json --argjson open "${open:-[]}" '([.[] | .bpid // empty] | unique) as $closed | (($t[0].tasks.pending // []) | map(.id)) as $pending | [$closed[] | select(. as $w | ($pending | index($w)) and (($open | index($w)) | not))] | join(",")'
```

A WO qualifies only when it has a completed bpid task, is still in the
tracker's `tasks.pending`, **and** no pending or `+ACTIVE` task carries its
bpid. A WO tracked as several tasks is not drained when one follow-up closes
while its main task is still open (#3173). This matches the `UNDRAINED_WOS`
computation in `session-survey.sh`.
