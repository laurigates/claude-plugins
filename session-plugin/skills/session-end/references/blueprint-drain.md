# session-end — Blueprint Drain Wave

## Blueprint auto-drain (ADR-0020 level 1)

When the qualifying repo's
`docs/blueprint/manifest.json` enables and opts the feature-tracker-sync task
into auto-running at autonomy level ≥ 1, that pass is **auto-confirmed** —
leave it out of the Step 3 question, run it in Step 4 order, and report a
one-line receipt in Step 5. All other passes still go through the Step 3
confirmation. The gate (the `jq` command in SKILL.md Step 2) requires all
three fields (issue #2358): `autonomy_level >= 1`, `enabled == true`, and
`auto_run == true`.

For why all three are required and the safe default for a missing `enabled`
key, see [../REFERENCE.md](../REFERENCE.md).

## Re-derive the drain wave (Step 4.3)

```sh
task bpid.any: status:completed export 2>/dev/null | jq -r --slurpfile t docs/blueprint/feature-tracker.json '([.[] | .bpid // empty] | unique) as $closed | (($t[0].tasks.pending // []) | map(.id)) as $pending | [$closed[] | select(. as $w | $pending | index($w))] | join(",")'
```
