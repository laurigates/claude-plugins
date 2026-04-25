---
created: 2026-04-25
modified: 2026-04-25
reviewed: 2026-04-25
description: |
  Audit user stories against codebase capabilities and tests, producing a tier-ranked
  coverage gap report. Use when the user asks to "audit stories", run a "story audit"
  / "coverage audit" / "PRD reconciliation", surface PRD↔code drift, identify untested
  critical paths, or find "implicit stories" that exist in code but never made it back
  into the PRD. Read-only — writes a single audit artifact under docs/blueprint/audits/.
args: "[--scope <area>] [--prd <path>] [--no-write] [--report-only]"
argument-hint: "--scope auth to limit; --prd docs/prds/PRD-001.md to override; --no-write skips artifact"
allowed-tools: Read, Write, Glob, Grep, Bash, Task, AskUserQuestion
name: blueprint-story-audit
---

# /blueprint:story-audit

Reconcile what the codebase actually does against what the PRD says it should do, then map every story to its tests and rank the gaps. Produces one durable artifact: `docs/blueprint/audits/<date>-story-audit.md`.

**Usage**: `/blueprint:story-audit [--scope <area>] [--prd <path>] [--no-write] [--report-only]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Auditing PRD↔code drift before a release or planning round | Drafting a brand-new PRD from scratch (`/blueprint:derive-prd`) |
| Finding untested critical paths through the user-story lens | Mining commits for missing tests (`/blueprint:derive-tests`) |
| Surfacing "implicit stories" — code-only features missing from PRD | Validating ADR relationships (`/blueprint:adr-validate`) |
| Producing a single artifact the team can act on top-to-bottom | Listing existing blueprint docs (`/blueprint:docs-list`) |

This skill is **read-only** apart from the audit artifact. PRD edits live in `/blueprint:story-reconcile`; agent dispatch for gap-fill work lives in `/blueprint:work-order`.

## Context

- Blueprint manifest: !`find docs/blueprint -maxdepth 1 -name 'manifest.json'`
- PRD directory: !`find docs -maxdepth 1 -name 'prds' -type d`
- PRD files: !`find docs/prds -maxdepth 1 -name '*.md'`
- Audits directory: !`find docs/blueprint -maxdepth 1 -name 'audits' -type d`
- Existing audits: !`find docs/blueprint/audits -maxdepth 1 -name '*.md'`
- Test directories: !`find . -maxdepth 3 -type d \( -name tests -o -name __tests__ -o -name test -o -name spec \) -not -path '*/node_modules/*'`
- Repo root: !`git rev-parse --show-toplevel`
- Today: !`date -u +%Y-%m-%d`

## Parameters

Parse `$ARGUMENTS`:

- `--scope <area>`: Limit discovery to a single capability area (e.g. `auth`, `image-detection`). Skips areas whose entry-point paths don't match the scope. Default: full repo.
- `--prd <path>`: Override PRD auto-detection. Repeatable — pass multiple `--prd` flags for multi-PRD projects. Default: every `*.md` directly under `docs/prds/`.
- `--no-write`: Print the audit to the conversation only; don't write to `docs/blueprint/audits/`.
- `--report-only`: Skip the Step 8 "What next?" prompt. Useful when running this skill from another orchestrator.

## Execution

Execute this audit workflow. Each step is required unless its inputs are missing — in that case, note the missing input in the artifact and continue.

### Step 1: Gather discovery inputs in parallel

Spawn three Explore subagents via the Task tool **in parallel** (single message, three tool calls). Each agent returns a structured findings list with `file:line` evidence; do **not** ask any agent to write the audit itself.

Agent 1 — **Capability map**:

> Survey this codebase and list every user-facing capability. Group by area
> (auth, billing, search, …). For each capability emit one row:
> `<area> | <capability> | <entry-point file:line> | <kind>` where kind is
> `route`, `cli`, `event-handler`, `component`, `cron`, or `worker`.
> Flag dependencies that look declared-but-unused (imported library that
> never has its main API called). Cap output at 200 rows; if a project is
> larger, summarize tail areas as "+ N more in <area>". Read-only.

Agent 2 — **Story extraction**:

> Read every PRD under {PRD paths from --prd or auto-detected}. Emit one
> row per stated user story or functional requirement:
> `<PRD-id> | <story-id-or-section> | <verbatim user-visible behaviour>
> | <linked deps if any>`. Also list any "Known Drift" or status-marked
> entries verbatim. Don't infer — only extract. Read-only.

Agent 3 — **Test inventory**:

> List every test file under {test directories from Context}. For each
> file emit: `<file> | <describe-or-suite> | <test-count> | <skipped-or-todo-count>`.
> When a file has a top-level comment or describe block citing a story
> ID (PRD-NNN, FR-N.N, story-name), include it. Read-only.

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

| Tier | Combination | Examples |
|------|-------------|----------|
| 1 — **critical untested** | core capability × zero tests | state machines, auth, payment paths |
| 2 — **partial coverage** | core capability × `~` confidence tests only | UI flows tested only at the unit level |
| 3 — **declared drift** | `❌ missing` PRD story | OCR named in PRD, never implemented |
| 4 — **implicit candidates** | `🆕 candidate` from Step 2 | code-only features awaiting story promotion |
| 5 — **healthy** | `✅` with `✓` tests | reference for "what good looks like" |

The tier cutoff between core and non-core is heuristic: Agent 1's `kind` field is the strongest signal (`route` and `event-handler` lean core; `component` leans non-core). Document the cutoff used at the top of the artifact so the user can override.

### Step 5: Surface bugs the audit found

If Agent 3 reported `test.todo` / `xit` / `skip` blocks with comments that read like bug reports (rather than "not yet implemented"), collect them into a **Bugs surfaced by audit** section with `file:line` + verbatim comment. Do **not** auto-file issues; the user decides.

### Step 6: Compose the audit artifact

Use the template at [REFERENCE.md#audit-template](REFERENCE.md#audit-template) and fill all six sections:

1. **Summary** — counts and the headline number (e.g. "8 PRD requirements drift; 3 critical capability areas have zero tests")
2. **Capability map** — Agent 1's output, grouped by area
3. **Story inventory** — explicit (PRD) + candidate (code-only) lists
4. **Drift report** — table with the four-status enum from Step 2
5. **Coverage matrix** — story × tests with confidence column
6. **Tiered gap analysis** — Tier 1 → 5 with one-line "why this matters" per tier
7. **Bugs surfaced by audit** (only if Step 5 found any)

Set the artifact path to `docs/blueprint/audits/<YYYY-MM-DD>-story-audit.md` using the `Today` value from Context. If a file with that name exists, append `-N` (e.g. `-2`).

### Step 7: Write the artifact and update the manifest

Skip this step if `--no-write` is set; print the artifact to the conversation instead.

```bash
mkdir -p docs/blueprint/audits
# Write artifact via Write tool to the path computed in Step 6.
```

Update the task registry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg result "${AUDIT_RESULT:-success}" \
   --argjson stories "${STORY_COUNT:-0}" \
   --argjson gaps "${TIER1_GAP_COUNT:-0}" \
   '.task_registry["story-audit"].last_completed_at = $now |
    .task_registry["story-audit"].last_result = $result |
    .task_registry["story-audit"].stats.runs_total = ((.task_registry["story-audit"].stats.runs_total // 0) + 1) |
    .task_registry["story-audit"].stats.items_processed = $stories |
    .task_registry["story-audit"].stats.tier1_gaps = $gaps' \
   docs/blueprint/manifest.json > docs/blueprint/manifest.json.tmp \
   && mv docs/blueprint/manifest.json.tmp docs/blueprint/manifest.json
```

Where `AUDIT_RESULT` is `"success"`, `"{N} drift entries"`, or `"failed: {reason}"`.

### Step 8: Offer next actions

Skip this step if `--report-only` is set.

Use AskUserQuestion to offer the three downstream paths the audit unlocks:

- **Reconcile drift in the PRD** → run `/blueprint:story-reconcile` against this audit
- **Dispatch a work-order for a Tier-1 gap** → run `/blueprint:work-order` per row
- **I'll act on the artifact later** → exit; the artifact is the durable output

Don't loop. The audit is the durable artifact; the user owns the next step.

## Heuristics, templates, and edge cases

For the implicit-story detection heuristics by stack (TypeScript/Python/Go), the audit-artifact template, the tier-ranking rationale, and how the skill behaves with no PRD or no tests, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Count PRD files | `find docs/prds -maxdepth 1 -name '*.md'` |
| Count test files (TS/JS) | `find . -type f \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.spec.ts' \) -not -path '*/node_modules/*'` |
| Count test files (Python) | `find . -type f -name 'test_*.py' -not -path '*/.venv/*'` |
| Find skipped tests | `grep -rn -E "test\.(skip\|todo)\|xit\(\|@pytest.mark.skip" --include='*.test.*' --include='test_*.py'` |
| Detect declared deps | `jq -r '.dependencies // {} \| keys[]' package.json` (or `grep '^[a-z].*=' pyproject.toml`) |
| Check dep is imported | `grep -rln "from <pkg>\|import <pkg>\|require('<pkg>')" --include='*.ts' --include='*.py'` |
| Audit filename | `echo "docs/blueprint/audits/$(date -u +%Y-%m-%d)-story-audit.md"` |

---

For the audit-artifact template, implicit-story heuristics by language, and tier-ranking rationale, see [REFERENCE.md](REFERENCE.md).
