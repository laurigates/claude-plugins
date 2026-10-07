# evaluate-skill: headless rollout branch (`--harness headless`)

**Headless branch (`--harness headless`).** First confirm `command -v claude jq python3`
all resolve; if any is missing, report `headless-unavailable` and stop rather than
falling back (subagent and headless numbers are not comparable). Then per eval case
and run: `prepare_run.sh` as in item 1 of the subagent branch in
[SKILL.md § Step 4](../SKILL.md#step-4-run-evaluations); write the case's `prompt` to
`$RUN_DIR/prompt.txt`; apply its `fixture` (item 2), or `mktemp -d` an empty workdir
**outside the repo** (the script refuses a workdir inside it); then launch the child:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rollout_headless.sh \
  --run-dir "$RUN_DIR" --workdir "$WORKDIR" --prompt-file "$RUN_DIR/prompt.txt" \
  --plugin-dir "$(pwd)/<plugin-name>" --model haiku --max-budget-usd 0.25
```
Omit `--plugin-dir` for the baseline. It writes `transcript.md`, `trace.json`,
`workspace/` and `timing.json` into `$RUN_DIR` and prints a `=== HEADLESS ROLLOUT ===`
block: `STATUS=ERROR` is an ERROR cell; WARN issues (`foreign_hook`,
`session_id_leak`, `uncapped`) are findings to report. Tear the workdir down
afterwards; the snapshot is already in `$RUN_DIR/workspace/`. Do not perform the
eval prompt yourself on this branch.
