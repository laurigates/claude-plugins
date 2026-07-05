---
name: blueprint-autopilot
description: Run due blueprint maintenance ambiently at autonomy level 2+. Use when a drift nudge reports blueprint tasks due or suggests /blueprint:autopilot.
allowed-tools: Read, Glob, Grep, Bash, Task
created: 2026-07-05
modified: 2026-07-05
reviewed: 2026-07-05
---

# blueprint-autopilot

The level-2 executor of the ADR-0020 autonomy model: runs due
**agent-judgment** maintenance tasks and (optionally) drafts work-order
proposals — quietly, with a one-line receipt. The inverse of
`/blueprint:execute`: no menus, no questions, act then report.

## When to Use This Skill

| Use this skill when... | Use /blueprint:execute instead when... |
|------------------------|----------------------------------------|
| The session-start drift nudge says blueprint tasks are due (`→ /blueprint:autopilot`) | The user wants an interactive "what's next?" menu |
| `automation.autonomy_level` ≥ 2 and ambient maintenance should just happen | The user wants to drive each action themselves |
| A work-order proposal should be drafted from a ready PRP without interrupting the user | The user wants to create a real work order now (`/blueprint:work-order`) |

## Context

- Automation config: !`bash ${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh`
- Due tasks (report mode, no writes): !`bash ${CLAUDE_SKILL_DIR}/../../scripts/blueprint-autorun.sh --report`

## Execution

Execute this autopilot pass:

### Step 1: Gate on autonomy level

Read `AUTONOMY_LEVEL` from the Context automation config. If it is **below
2**, stop immediately with the single line
`Autopilot inactive (autonomy_level N) — raise automation.autonomy_level in docs/blueprint/manifest.json to enable.`
Nothing else. Also stop (silently, one line) when `BLUEPRINT_AUTORUN_DISABLE=1`
is set in the environment.

### Step 2: Run due agent-judgment tasks (budget: 2 per pass)

From the Context `--report` output, collect the `DUE_AGENT_TASKS` list. Take
at most the **first 2** (session token budget — the rest surface again next
session). For each task, dispatch ONE subagent (Task tool) with a focused
brief:

- `adr-validate` → run the `/blueprint:adr-validate --report-only` procedure;
  return the findings summary only
- `feature-tracker-sync` → run the full-sync reconciliation in report-then-apply
  form, applying only unambiguous updates (drain evidence-backed completed WOs,
  recompute stats); ambiguous discrepancies are reported, not resolved
- `story-audit` → run the audit and write only its dated artifact under
  `docs/blueprint/audits/`
- any other task → run its skill's `--report-only`/dry-run form; never its
  mutating form

Each task's brief MUST state: work quietly, never `AskUserQuestion` (autopilot
runs unattended), and return a one-line result. Tasks whose skills would
require interactive confirmation for writes stay report-only here — autopilot
never bypasses a write gate.

After a task's subagent returns successfully, record completion in the
manifest:

```bash
jq --arg task "<task>" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.task_registry[$task].last_completed_at = $ts |
    .task_registry[$task].last_result = "ok (autopilot)" |
    .task_registry[$task].stats.runs = ((.task_registry[$task].stats.runs // 0) + 1)' \
   docs/blueprint/manifest.json > docs/blueprint/manifest.json.tmp \
   && mv docs/blueprint/manifest.json.tmp docs/blueprint/manifest.json
```

On a failed subagent, record `last_result = "error: <one-line reason>"` but do
NOT update `last_completed_at` (the task stays due).

### Step 3: Work-order auto-draft (only when `WO_AUTO_DRAFT=true`)

Skip this step entirely unless the Context config shows `WO_AUTO_DRAFT=true`.
Work-order **creation stays human-only** (`/blueprint:work-order` keeps
`disable-model-invocation: true` — never invoke it from autopilot). Autopilot
may only file *proposals*:

1. **Find ready PRPs**: scan `docs/prps/*.md` frontmatter for
   `confidence: 9` or higher (the `confidence-scoring` bar for delegation).
2. **Exclude PRPs that already have a work order or draft**: a WO exists when
   the manifest `id_registry` maps the PRP to a `WO-*` document, when a tracker
   `tasks.pending` entry carries `source: <PRP-id>`, or when an open GitHub
   issue labeled `work-order-draft` or `work-order` names the PRP id:

   ```bash
   gh issue list --state open --label work-order-draft --limit 100 --json number,title
   gh issue list --state open --label work-order --limit 100 --json number,title
   ```

3. **Cap**: if ≥ 5 open `work-order-draft` issues exist, draft nothing and
   note the cap in the receipt.
4. **File the draft** for each remaining ready PRP (at most 2 per pass):
   a GitHub issue titled `[work-order-draft] <PRP-id>: <PRP title>`, labeled
   `work-order-draft`, whose body is the full work-order packet built from the
   PRP (objective, minimal context, TDD requirements copied verbatim, success
   criteria, file list) plus the promotion instruction:
   `Promote with /blueprint:work-order --from-issue <N>`.
   Create the label first if missing
   (`gh label create work-order-draft --description "Auto-drafted work-order proposal (ADR-0020)" --color FBCA04`).
5. **No GitHub remote / `gh` unauthenticated**: write local draft files to
   `docs/blueprint/work-orders/drafts/NNN-<slug>.md` instead (same packet,
   `status: draft` frontmatter). Never touch `tasks.pending` or the
   `id_registry` — those mutate at promotion time only.

### Step 4: One-line receipt

End with exactly one summary line, e.g.:
`Autopilot: ran adr-validate (2 findings), feature-tracker-sync (1 WO drained); drafted 1 work-order proposal (#214).`
If nothing was due and nothing drafted:
`Autopilot: nothing due.`

## Guardrails

- Never `AskUserQuestion`; never end on a question. Autopilot is fire-and-report.
- Never invoke `/blueprint:work-order` or `/blueprint:prp-execute` (human-only
  by design; the draft-issue side channel is the only WO surface here).
- Bounded per pass: ≤ 2 agent tasks, ≤ 2 drafts, draft cap 5 open issues — no
  loops, no self-continuation (see `.claude/rules/loop-integrity.md`).
- `enabled: false` tasks never run regardless of level.
- Drafts are additive and closable; closing a `work-order-draft` issue is a
  valid human veto and autopilot re-drafts only if the PRP still qualifies AND
  no open draft exists (a closed draft for the same PRP id counts as a veto —
  check `--state all` before re-drafting and skip PRPs with a closed,
  unpromoted draft).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Gate + config in one call | `bash <plugin>/scripts/get-automation-config.sh` |
| Due-ness without writes | `bash <plugin>/scripts/blueprint-autorun.sh --report` |
| Draft dedupe (parallel-safe) | `gh issue list --state all --label work-order-draft --limit 100 --json number,title,state` |
| Kill switch | `BLUEPRINT_AUTORUN_DISABLE=1` |
