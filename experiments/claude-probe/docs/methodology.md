# Methodology — claude-probe

## Research question

Does replacing Claude Code's default system prompt with a minimal
bespoke prompt (plus the user's global rules + plugin infrastructure)
improve, degrade, or leave unchanged the quality of its work on a
representative set of tasks?

The hypothesis is that the default prompt duplicates and occasionally
contradicts the global rules + plugin layer (see
`docs/decision-analysis.md`), so a trimmed prompt should *at least not
harm* and *may reduce token waste and friction*.

## Variables

| Axis | Values | Notes |
|---|---|---|
| Model / thinking | `opus-xhigh`, `opus-medium` | Fixed via `conditions.yaml` |
| System prompt | `default` (none) vs `probe` (`prompts/probe.md`) | `--system-prompt` replaces |
| Tests | `tests/*.yaml` | Start with 8 seeds |
| Runs | 3 per cell | Samples the model's stochasticity |

Four conditions × 8 tests × 3 runs = 96 invocations per full suite.

## Invocation

Each run is headless:

```sh
claude -p "<test prompt>" \
  --model "$MODEL" \
  --output-format stream-json --verbose \
  --dangerously-skip-permissions \
  [--system-prompt "$(cat prompts/probe.md)"]
```

- `stream-json` yields a line-delimited event stream including
  `tool_use` blocks — essential for deterministic scoring.
- Fresh process per run (no prior conversation context).
- Working directory = repo root (plugins + settings live here).

## Scoring

Two layers, composable per test case:

### 1. Deterministic checks (`score-run.py`)

| Type | Asserts |
|---|---|
| `tool_used` | A specific tool was called (optionally with an arg-pattern regex) |
| `tool_not_used` | A specific tool was *not* called |
| `max_turns` | Assistant turn count ≤ N |
| `max_output_tokens` | Output-token total ≤ N |
| `output_matches` | Final assistant text matches a regex |
| `output_not_matches` | Final assistant text does not match a regex |

### 2. LLM-as-judge (`llm-judge.py`)

For fuzzy criteria — "did the summary include the three key points?",
"is the answer factually correct?". The judge runs with:

- **No** `--system-prompt` override (judge uses default Claude Code
  prompt, so its behaviour is not the condition under test).
- A cheap model (`claude-haiku-4-5-20251001` by default; override via
  `PROBE_JUDGE_MODEL`).
- A strict verdict format: first line is
  `VERDICT: PASS|FAIL|INDETERMINATE`.

The judge never sees the system-prompt condition of the transcript it
scores — blinding prevents the judge from rewarding the condition it
recognises.

## Test case format (`tests/<id>.yaml`)

```yaml
description: One-line intent
prompt: |
  <the message sent to the model under test>
checks:
  - id: used-glob
    type: tool_used
    spec: Glob
  - id: no-find-bash
    type: tool_not_used
    spec:
      name: Bash
      arg_pattern: "^find\\b"
  - id: concise
    type: max_output_tokens
    value: 400
  - id: quality
    type: llm_judge
    rubric: |
      PASS if the response lists markdown files grouped by directory,
      one path per line. FAIL otherwise.
```

## Statistical reading

With 3 runs per cell, we can't make strong claims about small effects.
What we *can* read from the aggregate table:

- **Regressions** — a test that goes 3/3 on `default` but 0/3 on
  `probe` is a real signal; the probe is missing something.
- **Wins** — 0/3 → 3/3 suggests the default prompt was actively
  discouraging the desired behaviour.
- **Noisy** — 2/3 vs 3/3 is within sampling noise; raise runs to 5 or
  10 before concluding.

Use `compare.py`'s per-check breakdown (in `scores.tsv`) to see which
specific checks flipped.

## Iteration loop

1. Run `just run` → `just compare`.
2. For each probe-only regression, diff against the Piebald reference
   (`https://github.com/Piebald-AI/claude-code-system-prompts`) to find
   the default-prompt fragment that produced the missing behaviour.
3. Copy the relevant fragment into `prompts/probe.md`.
4. Re-run the affected test with `just run-one`.
5. Promote from adhoc back to full suite when local checks pass.

## Known limitations

- **Real cwd** means real plugins + real hooks affect every run. The
  experiment measures "override vs default *in this environment*", not
  "override vs default in the abstract".
- **Judge drift**: the default system prompt updates weekly. Pin the
  Claude Code version of the judge (`PROBE_JUDGE_MODEL` + manually
  locked `claude` binary) if comparing runs across weeks.
- **Fresh session**: our tests don't exercise long-conversation
  behaviour. The override's effect on multi-turn tasks is out of
  scope here.
