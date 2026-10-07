# ComfyUI conditionals — Gotchas

Predicate traps that produce a wrong branch without an error. Entry point: [`../SKILL.md`](../SKILL.md) § Gotchas.

## Gotchas

- **Floats and equality**: `easy compare` with `==` on FLOATs is a
  trap. Use `SimpleComparison` (epsilon-aware) or `easy compare` with
  `<` / `>` instead. `1.0 + 2.0 == 3.0` is True, but `0.1 + 0.2 == 0.3`
  is False.
- **Lazy branch + `ComfyExecutionBlocker`**: lazy nodes
  (`easy ifElse`, `ImpactConditionalBranch`) *won't* evaluate the
  unselected branch, but they pass through whatever node-graph value
  the selected branch produces — including an `ExecutionBlocker`
  sentinel. If both branches can emit blockers, plan the merge
  carefully.
- **`SimpleMathCondition` returns FLOAT** (1.0 / 0.0), not BOOLEAN.
  Pass through `ImpactCompare` (`> 0.5`) before feeding a switch that
  wants BOOLEAN.
- **`easy isNone` on a pipe**: pipes (`PIPE_LINE`) are tuples — `isNone`
  returns False on an empty pipe (the tuple exists, just with None
  fields). To detect missing pipe content, unpack with `pipeOut` and
  probe individual fields.
- **`AContainsB` is regex, not substring**: special characters need
  escaping. To do a plain substring check, escape with `\Q...\E` or
  use Python regex-special escapes manually.
