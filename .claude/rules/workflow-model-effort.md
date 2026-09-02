---
created: 2026-06-22
modified: 2026-09-02
reviewed: 2026-09-02
paths:
  - ".github/workflows/**"
---
# Workflow Model + Effort

The model/effort standard for every Claude invocation in `.github/workflows/*.yml`.
The sibling of `agent-development.md` § "Model Selection for Agents" — same model
(`opus`), different surface (workflow `--model`/`--effort` args, not agent frontmatter),
and a **deliberately weaker justification** spelled out below.

## The rule

> Every workflow that invokes Claude pins **`--model opus`** and sets an
> **explicit `--effort`** level. No `haiku`/`sonnet`; no implicit effort.

Enforced by `scripts/check-workflow-model.sh` (+ `scripts/tests/test-check-workflow-model.sh`),
wired into `.pre-commit-config.yaml` and the `Plugin: PR checks` workflow.

## Justification (honest version)

The agent-model standard rests on a contamination argument: a subagent's output
re-enters the main loop as a tool result, so a weak delegate degrades everything
downstream. **That argument does not apply here** — a workflow is a *top-level*
Claude invocation, not a subagent feeding a parent loop. The justification for
workflows is purely **cost-economics**, which still holds:

- Measured on the Opus 4.8 / Sonnet 4.6 generation: Opus at *low* effort beat
  Sonnet at *high* effort on both quality and token efficiency, because the
  per-token premium (Opus output ≈ 1.7× Sonnet) was outweighed by token
  *volume*. So `effort`, not `model`, is the cost lever. The `opus` alias
  resolves to Opus 5 (2.1.255+) and effort names do not carry across
  generations — the economics and their re-verification live in
  skill-development.md § Model Selection; the monthly audit below is what
  checks the picks still hold.
- **Haiku supports no `--effort` at all** — it cannot access the cost lever.
  `haiku → opus --effort low` is the natural replacement, not a downgrade.

This is the same conclusion as the agent migration (PR #1691), reached by a
narrower path. State it plainly when editing: we are not claiming workflows
contaminate a main loop.

## The `--effort` mechanism

`--effort <level>` is passed in the `claude_args` string (for
`anthropics/claude-code-action@v1`) or as a raw flag to `npx @anthropic-ai/claude-code`.
Valid levels: `low`, `medium`, `high`, `xhigh`, `max`. **Opus defaults to
`high`** — so effort must be set *explicitly* or the cost savings are forfeited
(this is what the guard's `missing_effort` check enforces).

## Effort by job shape

| Job shape | Effort | Examples |
|-----------|--------|----------|
| Mechanical / pre-computed (checklist, compliance enumeration, content split) | `low` | `plugin-pr-checks`, `scheduled-audits`, `release-pr-doc-audit`, `skill-splitter` |
| Structured triage / transformation with light judgment | `medium` | `changelog-review`, `obsidian-cli-changelog`, `research-radar` |
| Open-ended reasoning (diagnose-and-fix, merge-intent reconciliation) | `medium` | `github-workflow-auto-fix`, `auto-resolve-conflicts` |
| Interactive / human-facing | `medium` (never `low`; no `--max-turns` cap) | `claude` (@mentions) |

`--max-turns` bounds tool-call I/O, not reasoning depth — effort is the depth/cost lever. Re-check the cap when moving a workflow to Fable 5.1: it runs longer agentic turns, so a cap tuned on Opus 4.x can truncate a job that was completing; when a run exits on `max_turns`, use `ai-review-max-turns` (the `is_error` discriminator) before treating it as a task failure.

## Unattended prompts

Every non-interactive workflow prompt (all rows except `claude.yml` @mentions) runs with nobody to answer a question, so it carries one autonomy sentence, because Fable 5.1 occasionally announces a step ("I'll now run the tests") and ends the turn without the call: "This run is unattended: continue until the task is complete or blocked by something you cannot resolve; if you say you will run something, run it; do not end the turn with a question."

## Per-workflow table (canonical)

| Workflow | Model + effort | Rationale |
|----------|----------------|-----------|
| `plugin-pr-checks.yml` | `opus` / `low` | Mechanical checklist vs fixed rubric |
| `scheduled-audits.yml` | `opus` / `low` | Data pre-computed; Claude only formats |
| `release-pr-doc-audit.yml` | `opus` / `low` | Mechanical compliance; turns are for file reads |
| `skill-splitter.yml` | `opus` / `low` | Mechanical content split |
| `research-radar.yml` | `opus` / `medium` | Judging paper relevance is real reasoning |
| `changelog-review.yml` | — | **Out of scope**: invocation lives in the external `laurigates/.github` reusable workflow (`reusable-changelog-review.yml`), pinned there to opus/medium via input defaults (severity triage, the #1638 deprecation-miss class); the guard skips the thin caller (classification, not allowlist) |
| `obsidian-cli-changelog.yml` | `opus` / `medium` | Structured doc-to-skill transformation |
| `github-workflow-auto-fix.yml` | `opus` / `medium` | Diagnose + fix CI failures |
| `auto-resolve-conflicts.yml` (CLI) | `opus` / `medium` | Merge must understand both intents |
| `claude.yml` (@mentions) | `opus` / `medium` | Interactive; pinned explicitly, no turn cap |
| `claude-code-review.yml` | — | **Out of scope**: model lives in the external `laurigates/.github` reusable workflow; the guard skips it (classification, not allowlist) |

The recurring `Plugin: Workflow model audit` workflow re-evaluates these picks
monthly against real run health and output samples, and opens an issue with
up/down effort recommendations.

## Enforcement: classification

`check-workflow-model.sh` classifies each workflow file:

| Class | Detected by | Action |
|-------|-------------|--------|
| **Invoking** | `anthropics/claude-code-action` or `npx @anthropic-ai/claude-code` | Assert `--model opus` + a valid explicit `--effort` |
| **Reusable-only** | `uses: …/.github/…reusable-*.yml` with no direct invocation | Skip (model is upstream) |
| **No-invocation** | neither | Skip silently |

Failure types: `missing_model`, `non_opus_model`, `missing_effort`,
`invalid_effort`. Output follows `.claude/rules/structured-script-output.md`
(`=== WORKFLOW MODEL/EFFORT ===` / `STATUS=` / `ISSUE_COUNT=`).

## Related

- `.claude/rules/agent-development.md` § "Model Selection for Agents" — the subagent sibling (frontmatter `model: opus`, stronger contamination rationale)
- `.claude/rules/skill-development.md` — the opus-is-often-cheaper / effort-is-the-cost-lever economics
- `.claude/rules/workflow-naming.md` — the `<Domain>: <Action>` naming for the same workflow surface
- `.claude/rules/github-actions-security.md` — least-privilege + script-injection baseline for these workflows
- `.claude/rules/regression-testing.md` — the guard is this migration's regression check
