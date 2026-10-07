# evaluate-skill: eval fixtures (subagent branch)

## Apply (Step 4, item 2)

2. If the eval carries a `fixture` block, apply it to get an isolated workdir:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/apply_fixture.sh \
     --fixture '<eval.fixture JSON>' --repo-root "$(pwd)"
   ```
   Parse `WORKDIR=` (the subagent then operates there). Skip this for evals
   without a `fixture` — they run in the repo as before.

## Teardown (Step 4, item 7)

7. If a fixture was applied, tear it down after the transcript is copied out:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/apply_fixture.sh --teardown "$WORKDIR" --fixture '<eval.fixture JSON>'`.
