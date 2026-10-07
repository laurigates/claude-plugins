---
created: 2026-04-25
modified: 2026-09-26
reviewed: 2026-04-25
description: Audit user stories against codebase and tests for tier-ranked coverage gaps. Use when running story audit, PRD reconciliation, or surfacing PRD-code drift.
args: "[--scope <area>] [--prd <path>] [--no-write] [--report-only]"
argument-hint: "--scope auth to limit; --prd docs/prds/PRD-001.md to override; --no-write skips artifact"
allowed-tools: Read, Write, Glob, Grep, Bash, Task, AskUserQuestion
model: opus
name: blueprint-story-audit
---

# /blueprint:story-audit

Reconcile what the codebase actually does against what the PRD says it should do, then map every story to its tests and rank the gaps. Produces one durable artifact: `docs/blueprint/audits/<date>-story-audit.md`.

**Usage**: `/blueprint:story-audit [--scope <area>] [--prd <path>] [--no-write] [--report-only]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Auditing PRD↔code drift before a release or planning round | Drafting a brand-new PRD from scratch (`/blueprint:derive-plans`) |
| Finding untested critical paths through the user-story lens | Mining commits for missing tests (`/blueprint:derive-tests`) |
| Surfacing "implicit stories" — code-only features missing from PRD | Validating ADR relationships (`/blueprint:adr-validate`) |
| Producing a single artifact the team can act on top-to-bottom | Listing existing blueprint docs (`/blueprint:docs-list`) |

This skill is **read-only** apart from the audit artifact. PRD edits live in `/blueprint:story-reconcile`; agent dispatch for gap-fill work lives in `/blueprint:work-order`.

## Context

- Blueprint manifest: !`find . -path '*/docs/blueprint/*' -maxdepth 3 -name 'manifest.json'`
- PRD directory: !`find . -path '*/docs/prds' -maxdepth 2 -type d`
- PRD files: !`find . -path '*/docs/prds/*' -maxdepth 3 -name '*.md'`
- Audits directory: !`find . -path '*/docs/blueprint/audits' -maxdepth 3 -type d`
- Existing audits: !`find . -path '*/docs/blueprint/audits/*' -maxdepth 4 -name '*.md'`
- Test directories: !`find . -maxdepth 3 -type d \( -name tests -o -name __tests__ -o -name test -o -name spec \) -not -path '*/node_modules/*'`
- Repo root: !`git rev-parse --show-toplevel`
- Today: !`date -u +%Y-%m-%d`

## Parameters

Parse `$ARGUMENTS`:

- `--scope <area>`: Limit discovery to a single capability area (e.g. `auth`, `image-detection`). Skips areas whose entry-point paths don't match the scope. Default: full repo.
- `--prd <path>`: Override PRD auto-detection. Repeatable — pass multiple `--prd` flags for multi-PRD projects. Default: every `*.md` directly under `docs/prds/`.
- `--no-write`: Print the audit to the conversation only; don't write to `docs/blueprint/audits/`.
- `--report-only`: Skip the Step 8 "What next?" prompt. Useful when running this skill from another orchestrator.

## Workflow harness (template)

`workflows/blueprint-story-audit.workflow.js` ships beside this skill. **It is a TEMPLATE to adapt,
not a script to run verbatim.** Read it, then rewrite it for the work in front of you.

**Adapt freely:** the agent prompts, the per-PRD and per-test-root fan-out width, the discovery
globs that enumerate `args.prds` / `args.testRoots`, the tier-cutoff heuristic wording, and the
project-specific commands in the Agentic Optimizations table below.

**Preserve across any adaptation:** (a) the fan-out width comes from `args.prds` and
`args.testRoots` — the `## Context` block's `find` output, or the `--prd` flags — never from a
prose "for each PRD"; (b) the `DRIFT_STATUS`, `CONFIDENCE`, and `TIER` enums in the schemas, which
force a determinate verdict per row instead of a paragraph that reads like one, and the
`tierCutoff` field that makes Step 4's documented cutoff non-optional; (c) the `parallel()` at
Step 1 is a real barrier — every downstream join is a *cross-lane* fact (a capability with no
story; a story with no test), so no lane's output is usable until all three have landed.

**Agent budget:** 4 + PRDs + test roots — the capability sweep, join, bug triage
and compose, plus one story agent per PRD and one test agent per test root. The
scale guard asks before every run, because both lists come from `args`.

**Skip the harness when:** the repo has one PRD and one test directory — the modal case, which
collapses to three agents total (capability + story + test) and is a linear pass where the harness
is pure overhead. The steps below remain the authoritative description of *what* each stage must
produce; the harness only fixes *how* the work is split.

Two structural constraints the template encodes, and why its row caps are not divided across lanes: [references/workflow-harness.md](references/workflow-harness.md).

## Execution

Execute this audit workflow. Each step is required unless its inputs are missing — in that case, note the missing input in the artifact and continue.

### Step 1: Gather discovery inputs in parallel

Spawn three Explore subagents via the Task tool **in parallel** (single message, three tool calls). Each agent returns a structured findings list with `file:line` evidence; do **not** ask any agent to write the audit itself.

Give each agent its brief verbatim from [references/agent-briefs.md](references/agent-briefs.md): Agent 1 — **Capability map**, Agent 2 — **Story extraction**, Agent 3 — **Test inventory**.

Wait for all three to complete. If `--scope <area>` is set, filter Agent 1's rows to that area before moving on.

### Step 2: Diff capabilities against stories

Build the **drift report** by joining Agent 1's capability map against Agent 2's story inventory. For each capability:

| Status | Meaning |
|--------|---------|
| ✅ implemented | Capability has a matching PRD story |
| ⚠️ partial | PRD story exists but capability is missing significant sub-behaviour the story names |
| ❌ missing | PRD story has no matching capability — feature declared but not built |
| 🆕 candidate | Capability exists but no PRD story matches — implicit story |

Match on substring overlap of capability name vs story title, then verify with a quick file-level read where ambiguous. **Do not promote candidates into the PRD here** — that is `/blueprint:story-reconcile`'s job.

Also flag **declared-but-unused dependencies** from Agent 1's findings as `❌ missing` drift entries (e.g. "tesseract listed in package.json but never imported").

### Step 3: Map stories to tests

Build the **coverage matrix**: for every PRD story from Agent 2, find tests from Agent 3 that match by:

1. Explicit story-id reference in test file/describe (highest confidence)
2. File-path proximity (`auth/login.ts` → `auth/login.test.ts`)
3. Keyword overlap in test description vs story title (lowest confidence, mark as `~`)

Produce one row per story:

```
<story-id> | <linked tests> | <test-count> | <skipped/todo> | <confidence: ✓ / ~ / ✗>
```

Stories with **zero matched tests** become Tier-1 gap candidates.

### Step 4: Tier-rank the gaps

Apply this default ranking. Override per-row only if the user passed explicit guidance.

The five tiers (1 critical untested → 5 healthy) with their combinations and examples: [references/tier-ranking.md](references/tier-ranking.md).

The tier cutoff between core and non-core is heuristic: Agent 1's `kind` field is the strongest signal (`route` and `event-handler` lean core; `component` leans non-core). Document the cutoff used at the top of the artifact so the user can override.

### Step 5: Surface bugs the audit found

If Agent 3 reported `test.todo` / `xit` / `skip` blocks with comments that read like bug reports (rather than "not yet implemented"), collect them into a **Bugs surfaced by audit** section with `file:line` + verbatim comment. Do **not** auto-file issues; the user decides.

### Step 6: Compose the audit artifact

Fill all seven sections of the template at [REFERENCE.md#audit-template](REFERENCE.md#audit-template):

What goes in each section: [references/artifact-sections.md](references/artifact-sections.md).

Set the artifact path to `docs/blueprint/audits/<YYYY-MM-DD>-story-audit.md` using the `Today` value from Context. If a file with that name exists, append `-N` (e.g. `-2`).

### Step 7: Write the artifact and update the manifest

Skip this step if `--no-write` is set; print the artifact to the conversation instead.

```bash
mkdir -p docs/blueprint/audits
# Write artifact via Write tool to the path computed in Step 6.
```

Update the task registry in `docs/blueprint/manifest.json`. When the workflow harness ran, `AUDIT_RESULT`, `STORY_COUNT`, and `TIER1_GAP_COUNT` come from the composition agent's structured return (`auditResult`, `storyCount`, `tier1GapCount`) — do not recount them by hand:

Run the `jq` update in [references/manifest-update.md](references/manifest-update.md).

### Step 8: Offer next actions

Skip this step if `--report-only` is set.

Use AskUserQuestion to offer the three downstream paths the audit unlocks:

- **Reconcile drift in the PRD** → run `/blueprint:story-reconcile` against this audit
- **Dispatch a work-order for a Tier-1 gap** → recommend the user run `/blueprint:work-order` per row (a user-invocable command — surface it for the user to run, don't invoke it via the Skill tool)
- **I'll act on the artifact later** → exit; the artifact is the durable output

Don't loop. The audit is the durable artifact; the user owns the next step.

## Heuristics, templates, and edge cases

For the implicit-story detection heuristics by stack (TypeScript/Python/Go), the audit-artifact template, the tier-ranking rationale, and how the skill behaves with no PRD or no tests, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

Count/skip/dependency/filename commands: [references/agentic-optimizations.md](references/agentic-optimizations.md).

---

For the audit-artifact template, implicit-story heuristics by language, and tier-ranking rationale, see [REFERENCE.md](REFERENCE.md).
