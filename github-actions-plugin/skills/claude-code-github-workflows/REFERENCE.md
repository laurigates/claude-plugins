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
  env:
    GH_TOKEN: ${{ github.token }}
    REPORT_FILE: report.md
    R: ${{ github.repository }}
    N: ${{ github.event.pull_request.number }}
  run: |
    [ -s "${REPORT_FILE}" ] || { echo "::error::the agent produced no report"; exit 1; }
    { echo '<!-- report-marker -->'; grep -vFx '<!-- report-marker -->' "${REPORT_FILE}"; } > body.md
    jq -Rs '{body: .}' body.md | gh api -X POST "repos/${R}/issues/${N}/comments" --input -
```

**A missing report fails the job.** When this step is the only proof that the
agent produced anything, `exit 0` on a missing file turns every failed run green.
Relax it to `::warning::` and `exit 0` only where another step already fails the
job on a missing report, or where "nothing to report" is a legitimate outcome
the agent signals some other way (an empty file is still a file).

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

Four ways an AI-powered CI check reports something other than what happened.
All four look like a normal red or green tick:

| Mode | The check says | Reality | Where |
|---|---|---|---|
| Never ran | pass | path filter or disabled workflow skipped it | `github-actions-plugin:ai-review-max-turns` § a check that never ran |
| Red but unreadable | fail, no detail | a real finding it had no permission to publish | `github-actions-plugin:ai-review-max-turns` Cause 3 |
| Posted but unparseable | fail, "result discarded" | the result is published and correct | this section |
| Green but unpublished | pass | the agent was told to publish its own output (`git commit`/`git push`, a wiki or comment write), its calls were denied, and nothing reached the destination | this section; § Denials are a count |

Green but unpublished is the quietest of the four, because nothing about the run
is red. The `permission_denials_count` in the result is the only trace, and it
is a count, not the denied calls. The fix is the produce/publish split in
[§ The fix](#the-fix), with the publish step failing on a missing file.

> Evidence (ForumViriumHelsinki/infrastructure, a weekly summary job,
> 2026-07-20 to 2026-10-01): every run finished `success` with 2–9 denials, and
> no report reached the wiki in about ten weeks. Fixed in
> ForumViriumHelsinki/infrastructure#2526 by a workflow publish step that fails
> on a missing file and reads the result back.

The shared tell is that **the check's own message describes its parse, not the
work** — so read the artifact it claims is missing before believing it is
missing. One `gh pr view <n> --json comments` would have ended the case in [§ The failure shape](#the-failure-shape)
at any point.

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

## More claude-code-action v1 gotchas

Detail for the pointer in SKILL.md § claude-code-action v1 Gotchas. Each one
leaves a run that looks normal from the check alone.

### A `github.token` push meets the bot refusal

SKILL.md § Bots are blocked by default covers the `allowed_bots` input itself.
The same refusal hits a PR that a workflow pushed to with `github.token`: the
next run's `actor` is `github-actions[bot]`, GitHub holds it for approval, and
the approved attempt still fails here because `actor` stays the bot. The action
strips a trailing `[bot]` before comparing, so `allowed_bots: "github-actions"`
admits it; so does pushing with a PAT or App token instead. To recognise and
count these refusals in a repo's failed runs, see
`github-actions-plugin:ai-review-max-turns` (Cause 5, bot-actor refusal).

### A changed workflow can't be tested from a branch

When a `workflow_dispatch` runs a workflow file whose content differs from the
default branch's copy, the action exits before the agent starts:

```
Workflow validation failed. The workflow file must exist and have identical content to the version on the repository's default branch.
```

The step still reports **success**. Every later step then runs against no
output, and an `if: failure()` notifier fires on whichever step trips over the
gap: two branch runs of a fixed workflow each opened a spurious "summary
failed" issue. `steps.<id>.outputs.execution_file` is empty on such a run, so
gate the steps that consume the agent's output on it, and verify a workflow
change after merge with `gh workflow run <file>.yml` on the default branch, not
from the feature branch:

```yaml
- name: Publish the summary
  if: steps.claude.outputs.execution_file != ''
```

### Denials are a count

The printed result carries `permission_denials_count`, not the denied calls.
The full transcript, denials included, is written to
`$RUNNER_TEMP/claude-execution-output.json`. Read it with a fallback to that
fixed path, because `execution_file` can be empty (the validation skip leaves
it unset), and upload it so a run's tool calls stay readable afterwards:

```yaml
- name: Upload the execution log
  if: always()
  uses: actions/upload-artifact@v7
  with:
    name: claude-execution-output
    path: ${{ steps.claude.outputs.execution_file || format('{0}/claude-execution-output.json', runner.temp) }}
    if-no-files-found: ignore

- name: List denied tool calls
  if: always()
  env:
    EXEC_FILE: ${{ steps.claude.outputs.execution_file || format('{0}/claude-execution-output.json', runner.temp) }}
  run: |
    [ -f "$EXEC_FILE" ] || { echo "no execution file"; exit 0; }
    jq -r '.[] | select(.type == "result") | .permission_denials[]?
      | "\(.tool_name) \(.tool_input | tostring | .[0:160])"' "$EXEC_FILE"
```

A run can finish green with several denials and no published output; that mode
is in § The family (green but unpublished).

## A starter CLAUDE.md

Create `CLAUDE.md` in repository root to define coding standards:

```markdown
# Repository Guidelines for Claude Code

## Code Standards
- Use TypeScript strict mode
- Follow Airbnb style guide
- Maintain 90%+ test coverage
- Document all public APIs

## Development Workflow
- Run tests before committing: `npm test`
- Format with Prettier: `npm run format`
- Lint with ESLint: `npm run lint`

## Commit Messages
Follow Conventional Commits:
- feat: New features
- fix: Bug fixes
- docs: Documentation changes
- refactor: Code refactoring

## Testing Requirements
- Unit tests for all functions
- Integration tests for APIs
- E2E tests for critical flows

## Security
- Never commit secrets
- Validate all user inputs
- Use parameterized queries
- Follow OWASP guidelines
```
