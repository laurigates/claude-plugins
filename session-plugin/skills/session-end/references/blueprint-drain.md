# session-end — Blueprint Drain Wave

## Re-derive the drain wave (Step 4.3)

```sh
task bpid.any: status:completed export 2>/dev/null | jq -r --slurpfile t docs/blueprint/feature-tracker.json '([.[] | .bpid // empty] | unique) as $closed | (($t[0].tasks.pending // []) | map(.id)) as $pending | [$closed[] | select(. as $w | $pending | index($w))] | join(",")'
```
