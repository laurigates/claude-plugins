---
created: 2026-04-25
modified: 2026-05-04
reviewed: 2026-04-25
description: |
  Reconcile PRD requirements with the drift report from a /blueprint:story-audit. Use
  when the user wants to mark PRD entries as ✅ implemented / ⚠️ partial / ❌ missing
  based on the latest audit, add a "Known Drift" section to a PRD, or promote a candidate
  (code-only) story into the PRD. Mutates PRD files only — never touches source code.
args: "[--audit <path>] [--prd <path>] [--apply-all] [--dry-run]"
argument-hint: "--audit docs/blueprint/audits/2026-04-25-story-audit.md (defaults to latest)"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
model: opus
name: blueprint-story-reconcile
---

# /blueprint:story-reconcile

Apply the drift findings from `/blueprint:story-audit` back to the PRDs. Adds status markers, a `Known Drift` section, and (with consent) promotes candidate stories. Does **not** delete unimplemented requirements — they remain the roadmap.

**Usage**: `/blueprint:story-reconcile [--audit <path>] [--prd <path>] [--apply-all] [--dry-run]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Marking PRD requirements as implemented / partial / missing after an audit | Producing the audit itself (`/blueprint:story-audit`) |
| Adding a "Known Drift" section to a PRD | Generating PRDs from scratch (`/blueprint:derive-prd`) |
| Promoting a single candidate story into the PRD with user consent | Bulk-rewriting PRDs (this skill is deliberately conservative) |

This skill **only edits PRDs**. Code changes belong to `/blueprint:work-order`. Audit re-runs belong to `/blueprint:story-audit`.

## Context

- Latest audit: !`find docs/blueprint/audits -maxdepth 1 -name '*-story-audit.md'`
- PRD directory: !`find docs -maxdepth 1 -name 'prds' -type d`
- PRD files: !`find docs/prds -maxdepth 1 -name '*.md'`
- Manifest: !`find docs/blueprint -maxdepth 1 -name 'manifest.json'`
- Branch: !`git branch --show-current`
- Repo status: !`git status --porcelain=v2 --branch`

## Parameters

Parse `$ARGUMENTS`:

- `--audit <path>`: Path to the audit artifact. Default: most-recent file matching `docs/blueprint/audits/*-story-audit.md` (sort lexically — date-stamped names sort correctly).
- `--prd <path>`: Limit edits to a single PRD. Default: every PRD referenced by the audit's drift table.
- `--apply-all`: Skip per-row prompts and apply every drift entry as an edit. Use only when the audit was reviewed elsewhere.
- `--dry-run`: Show the planned edits as unified diffs without writing.

## Execution

Execute this PRD-reconciliation workflow.

### Step 1: Locate the audit artifact

1. If `--audit <path>` provided, read that file.
2. Otherwise, list `docs/blueprint/audits/*-story-audit.md`, pick the lexicographically last one (date-stamped names sort correctly).
3. If none found → abort with: "No audit artifact found. Run `/blueprint:story-audit` first."

### Step 2: Parse the drift report

Read the audit's **Drift Report** section (Section 4 in the canonical template). Extract every row into a structured list:

```
{ status: ✅|⚠️|❌|🆕, prd_ref: <id-or-null>, capability: <name>, evidence: <text> }
```

Skip `✅ implemented` rows — they're informational; reconcile only adds value for `⚠️`, `❌`, and `🆕`.

If the audit also has a **Story Inventory → Candidate** section, merge those rows into the `🆕` group with their `entry-point` evidence.

### Step 3: Group edits by PRD

For each non-`✅` drift entry, determine the target PRD:

| Status | Target PRD |
|--------|-----------|
| ⚠️ partial / ❌ missing | The PRD whose `prd_ref` matches the entry (e.g. `FR-2.3` → `docs/prds/PRD-002.md`) |
| 🆕 candidate | Ask the user which PRD to promote into; if no PRD covers the area, suggest creating a stub via `/blueprint:derive-prd` |

If `--prd <path>` is set, drop entries whose target PRD doesn't match.

### Step 4: Plan edits per PRD

For each target PRD, plan two kinds of edit:

**A. Inline status markers** for `⚠️` and `❌` entries — locate the line containing the requirement (search by `prd_ref` or substring of `capability`) and prepend the marker to the requirement line:

```
- FR-2.3 OCR support → server runs tesseract over uploads
```

becomes

```
- ❌ FR-2.3 OCR support → server runs tesseract over uploads (drift: dep declared but never imported)
```

**B. A "Known Drift" appendix** at the bottom of the PRD, in this exact format (idempotent — replace the section if it already exists):

```markdown
## Known Drift

> Tracked by audit: `docs/blueprint/audits/<YYYY-MM-DD>-story-audit.md`

| Status | Requirement | Evidence | Action |
|--------|-------------|----------|--------|
| ❌ | FR-2.3 OCR support | dep `tesseract` declared but never imported | <work-order id or "open"> |
| ⚠️ | FR-1.4 deskew on import | implemented but only for landscape orientation | open |
```

For `🆕` candidate entries (Step 3 mapped them to a PRD): append a new requirement row at the end of the relevant FR section, with explicit text:

```
- FR-N.M (candidate, promoted from audit <YYYY-MM-DD>): <verbatim capability name>
  Evidence: <entry-point file:line>
```

Do **not** renumber existing FRs — append at the end.

### Step 5: Confirm before writing

Skip this step when `--apply-all` is set.

For each PRD, show the planned edits as a unified diff and ask via AskUserQuestion:

- **Apply all edits to this PRD** — proceed
- **Apply some edits** — show each row individually for accept/skip
- **Skip this PRD** — no edits land
- **Cancel reconcile entirely** — exit with no changes

If `--dry-run` is set, print the diffs and exit without prompting.

### Step 6: Apply edits

For each accepted edit, use the Edit tool to modify the PRD. Keep edits **idempotent**: re-running this skill against the same audit + same PRD must produce no further changes (the inline marker is already there; the Known Drift table already reflects the same rows).

After all PRD edits land:

```bash
git status --porcelain=v2 docs/prds/
```

If any non-PRD file shows up as modified → abort and report. This skill must only touch PRDs.

### Step 7: Update the manifest

Update the task registry entry:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg result "${RECONCILE_RESULT:-success}" \
   --argjson edits "${EDITS_APPLIED:-0}" \
   --argjson prds "${PRDS_TOUCHED:-0}" \
   '.task_registry["story-reconcile"].last_completed_at = $now |
    .task_registry["story-reconcile"].last_result = $result |
    .task_registry["story-reconcile"].stats.runs_total = ((.task_registry["story-reconcile"].stats.runs_total // 0) + 1) |
    .task_registry["story-reconcile"].stats.items_processed = $edits |
    .task_registry["story-reconcile"].stats.prds_touched = $prds' \
   docs/blueprint/manifest.json > docs/blueprint/manifest.json.tmp \
   && mv docs/blueprint/manifest.json.tmp docs/blueprint/manifest.json
```

### Step 8: Suggest the commit

Print the suggested commit message but **do not commit automatically** — the user owns the commit boundary:

```
docs(<scope>): reconcile PRD with story-audit <YYYY-MM-DD>

Refs docs/blueprint/audits/<YYYY-MM-DD>-story-audit.md

- Marked <N> drift entries (✅ <a> ⚠️ <b> ❌ <c>)
- Promoted <N> candidate stories
- Touched: <list of PRD paths>
```

Choose `<scope>` as the PRD prefix shared by edits (e.g. `prd-001`) or omit if multiple PRDs were touched.

### Step 9: Hand off the next action

Use AskUserQuestion to surface the obvious follow-on:

- **Open work-orders for ❌ entries** → invoke `/blueprint:work-order` per Tier-3 row
- **Re-run the audit to confirm green** → invoke `/blueprint:story-audit`
- **I'm done** → exit

## What this skill deliberately does NOT do

| Off-limits | Why |
|------------|-----|
| Edit source code | Code changes go through `/blueprint:work-order` so the change has a TDD packet behind it |
| Delete unimplemented requirements | They are the roadmap. `❌` is a tracked status, not a delete signal. |
| Auto-create GitHub issues for drift | Audit + reconcile are local artifacts; issue filing is an explicit user action |
| Renumber FRs to "tidy up" | FR numbers are referenced from tests, commits, and other PRDs — renumbering is an unsafe, non-idempotent edit |
| Commit changes | Commit boundaries are the user's decision; this skill prints the suggested message and stops |

## Idempotency

Re-running this skill against the same audit + same PRDs must be a no-op. The two mechanisms:

1. Inline status markers (`⚠️ `, `❌ `, `🆕 `) are detected before insertion. If the requirement line already starts with the right marker, skip.
2. The `## Known Drift` section is **replaced wholesale** by the new content, never appended.

If a re-run produces changes, that is a bug — file it.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find latest audit | `find docs/blueprint/audits -maxdepth 1 -name '*-story-audit.md'` |
| Show audit drift section | `awk '/^## 4\. Drift Report/,/^## 5\. /' <audit-path>` |
| Detect existing Known Drift | `grep -c '^## Known Drift' docs/prds/*.md` |
| Locate FR by id | `grep -n 'FR-2\.3' docs/prds/*.md` |
| Count PRD files | `find docs/prds -maxdepth 1 -name '*.md'` |
| Verify only-PRDs touched | `git status --porcelain=v2 docs/prds/` |

---

For drift-marker conventions, the full Known-Drift section format, and idempotency edge cases, see [REFERENCE.md](REFERENCE.md).
