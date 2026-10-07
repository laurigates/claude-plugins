# evaluate-skill: command and flag reference

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Inspect skill eval setup | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin <plugin> --skill <skill>` |
| Print evals JSON | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin <plugin> --skill <skill> --print-evals` |
| Prepare a run directory | `bash evaluate-plugin/scripts/prepare_run.sh --skill-dir <plugin>/skills/<skill> --eval-id <id> --run <N>` |
| Aggregate results | `bash evaluate-plugin/scripts/aggregate_benchmark.sh <plugin>` |
| One headless rollout | `bash evaluate-plugin/scripts/rollout_headless.sh --run-dir <d> --workdir <tmp> --prompt-file <f> --plugin-dir <plugin> --max-budget-usd 0.25` |
| Trigger-eval plan + cost | `python3 evaluate-plugin/scripts/run_trigger_evals.py --skill-dir <plugin>/skills/<skill> --dry-run` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--create-evals` | Generate eval cases from SKILL.md analysis |
| `--runs N` | Number of runs per eval case (default: 1) |
| `--baseline` | Run without skill for comparison |
| `--harness headless` | Real `claude -p` rollouts with the plugin loaded (default: `subagent`) |
| `--triggers` / `--triggers-only` | Also / only run the `triggers` block's routing evals |
