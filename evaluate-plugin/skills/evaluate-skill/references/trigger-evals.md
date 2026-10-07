# evaluate-skill: trigger evals (Step 4b)

If `evals.json` has a `triggers` block, check the plan and its worst-case cost first,
then run it (each prompt is a real headless child killed at its first `Skill` call):
```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/run_trigger_evals.py --skill-dir <plugin-name>/skills/<skill-name> --dry-run
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/run_trigger_evals.py --skill-dir <plugin-name>/skills/<skill-name>
```
Report recall, precision, the false positives by `near_miss_of`, and `STATUS`. Results
at the default `--runs 1` are noisy (a missed threshold is WARN, not ERROR); pass
`--runs 3` before acting on them. No `triggers` block: say so and continue.
