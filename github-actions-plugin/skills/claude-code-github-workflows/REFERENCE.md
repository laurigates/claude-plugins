# Claude Code GitHub Workflows — Reference

Supporting material for [SKILL.md](SKILL.md), loaded on demand.

## A marker the model has to emit is not a machine-readable marker

Promoted from the always-loaded `agent-emitted-markers-are-not-machine-readable.md`
portfolio rule, whose stub keeps the gate line.

When a CI job parses an agent's output — greps for a sentinel, reads a fenced
JSON block, counts a marked comment — the parseable part is usually specified in
the prompt and produced by the model. That arrangement has no mechanism. The
model reproduces what a reader would see and drops what a reader would not, and
the gate then reports on the marker rather than on the work.

> The law: **whatever CI parses must be written by the deterministic side.** The
> agent produces content; the harness adds the structure it will later read.

### The failure shape

A docs-validation workflow counted PR comments matching
`<!-- docs-validation-report -->` and failed the job when it found none. The
agent was told to put that marker on the first line of the comment it posted.
It never did: across three PRs the agent posted one, four and three reports,
and **none** carried the marker. Every one opened with a
`# Documentation Validation Report` heading instead. So the job failed with
*"the validation ran but its result was discarded"* about a report sitting in
plain view on the PR — on every non-skipping run, for as long as the check had
been live.

The omission has a mechanical cause worth knowing, because it will repeat: the
instruction lived in the command file's **Output Format** block, where the marker
is the first line of a fenced example. A model reading that block reproduces the
visible heading and drops the invisible HTML comment above it. Restating the
requirement in prose above the fence does not fix it — the fence is what gets
copied.

### The fix

Split producing from publishing. The agent writes a file; a workflow step adds
the marker and posts it:

```yaml
- name: Publish the report
  run: |
    [ -s "${REPORT_FILE}" ] || { echo "::warning::nothing to publish"; exit 0; }
    { echo '<!-- report-marker -->'; grep -vFx '<!-- report-marker -->' "${REPORT_FILE}"; } > body.md
    jq -Rs '{body: .}' body.md | gh api -X POST "repos/${R}/issues/${N}/comments" --input -
```

Three properties that make it hold:

- **The marker cannot be forgotten**, because nothing is asked to remember it.
- **The gate changes meaning.** It now tests publication rather than instruction
  following, so its failure has exactly one cause left upstream of it — no
  report file — and the error message can say so.
- **`jq -Rs` builds the body.** Agent reports carry backticks and quotes; no
  shell-quoted `--field` survives them.

Strip a marker the agent added anyway (`grep -vFx`) so it appears once, and
prefer editing the existing marked comment over appending — an agent-posted
report accumulates one comment per run otherwise.

### The family

Three ways an AI-powered CI check reports something other than what happened.
All three look like a normal red or green tick:

| Mode | The check says | Reality | Where |
|---|---|---|---|
| Never ran | pass | path filter or disabled workflow skipped it | `github-actions-plugin:ai-review-max-turns` § a check that never ran |
| Red but unreadable | fail, no detail | a real finding it had no permission to publish | `github-actions-plugin:ai-review-max-turns` Cause 3 |
| Posted but unparseable | fail, "result discarded" | the result is published and correct | this section |

The shared tell is that **the check's own message describes its parse, not the
work** — so read the artifact it claims is missing before believing it is
missing. One `gh pr view <n> --json comments` would have ended the case above at
any point.

A related consequence: a "no code change" line in an agent's commit message is
also model-emitted text, so it is not a skip signal CI may parse either (see the
runaway-loop notes in `ai-review-max-turns` REFERENCE.md).

### When it bites

- Any workflow that greps agent output for a sentinel, an exit verdict, a
  `<!-- -->` marker, or a fenced block it then parses.
- Cheap models specifically. The failure is a formatting omission, not a
  reasoning one, and the smaller the model the more reliably it reproduces the
  visible shape and drops the invisible one.
- Structured-output contracts get this right for the same reason: the schema is
  enforced by the runtime, not requested in the prompt. Prefer one where the
  surface supports it — `--json-schema` and the `structured_output` output
  (SKILL.md § Outputs are fixed).

### Related

- `offload-to-deterministic-substrate.md` (in `~/.claude/rules/`) — the parent
  principle; this is its CI-parsing instance
- `github-actions-plugin:release-artifact-verification` — same law after the
  fact: go look at the artifact rather than trusting the pipeline's account of it
