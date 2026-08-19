---
created: 2026-01-15
modified: 2026-07-26
reviewed: 2026-07-26
description: Validate ADR relationships, domain consistency, and duplicate ADR numbers. Use when auditing ADRs before release, finding broken supersedes/extends links, cycles, or number collisions.
args: "[--report-only]"
argument-hint: "--report-only to validate without prompting for fixes"
allowed-tools: Read, Bash, Glob, Grep, Edit, AskUserQuestion
name: blueprint-adr-validate
---

# /blueprint:adr-validate

Validate Architecture Decision Records for relationship consistency, reference integrity, and domain conflicts.

**Usage**: `/blueprint:adr-validate [--report-only]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Maintaining ADR integrity before releases | Creating new ADRs (use `/blueprint:derive-plans`) |
| Auditing after refactoring or changes | Quick one-time documentation review |
| Regular documentation review process | General ADR reading |

## Context

- ADR directory exists: !`find . -path '*/docs/adrs' -maxdepth 2 -type d`
- ADR count: !`find . -path '*/docs/adrs/*' -name "*.md" -type f`
- Domain-tagged ADRs: !`find . -path '*/docs/adrs/*' -maxdepth 3 -name '*.md' -exec grep -l "^domain:" {} +`
- Flag: !`echo "${1:---}"`

## Parameters

Parse `$ARGUMENTS`:

- `--report-only`: Output validation report without prompting for fixes
  - Default: Interactive mode with remediation options

## Execution

Execute complete ADR validation and remediation workflow:

### Step 1: Discover all ADRs

1. Check for ADR directory at `docs/adrs/`
2. If missing → Error: "No ADRs found in docs/adrs/"
3. Parse all ADR files: `ls docs/adrs/*.md`
4. Extract frontmatter for each ADR: number, id, created, modified, status, domain, supersedes, superseded-by, extends, relates-to

### Step 2: Validate reference integrity

For each ADR, validate:

1. **supersedes references**: Verify target exists, target status = "Superseded", target has reciprocal superseded-by
2. **extends references**: Verify target exists, warn if target is "Superseded"
3. **related references**: Verify all targets exist, warn if one-way links
4. **self-references**: Flag if ADR references itself
5. **circular chains**: Detect cycles in supersession graph
6. **Cross-workspace references** (v3.3.0+, manifests with `workspaces.role`):
   Recognise these reference forms in supersedes/extends/related fields:
   - `ADR-NNN` — local to the current workspace (existing behaviour).
   - `<workspace-path>/ADR-NNN` — points into a sibling/child workspace. Resolve
     by reading `<workspace-path>/docs/adrs/` from the monorepo root. Warn if
     the workspace is not listed in root `workspaces.children`.
   - `/ADR-NNN` — points at the monorepo root's ADR set. Resolve using the
     manifest's `workspaces.root_relative_path` (for child manifests) or the
     current directory (for root manifests).
   Unresolved cross-workspace refs are reported as warnings (not errors) so
   they do not block validation during migration.

See [REFERENCE.md](REFERENCE.md#validation-rules) for detailed checks.

### Step 2b: Detect ADR-number collisions and index drift

ADR numbers are chosen at branch time but only claimed at merge time, so two
in-flight ADR PRs can pick the same number and both land (issue #1585 — the FVH
infrastructure #2015 collision where two ADRs both claimed `0038`). Run the
deterministic guard:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-adr-numbers.sh --project-dir "$(pwd)"
```

It emits the structured `STATUS=` / `ISSUE_COUNT=` convention and reports four
classes (see [REFERENCE.md](REFERENCE.md#validation-rules)):

- `duplicate_adr_number` (ERROR) — two files claim the same number, by `NNNN-title.md` **filename** or by a frontmatter `id: ADR-NNNN` claim. The message names the source (`basename` / `frontmatter`), so a claim from a file with no number in its name is legible.
- `adr_number_collision` (ERROR) — a working-tree ADR claims a number a **different** file already holds on the base ref (`origin/main`) — the pre-merge parallel-PR case, caught before the second PR merges.
- `adr_registry_mismatch` (ERROR) — a file claims `ADR-NNNN` but the manifest `id_registry` maps that number to a different path. The registry is the only arbiter resolving id → path unambiguously: two files can both *say* `ADR-0016`, only one can be registered. Silent with no manifest / no `id_registry`.
- `adr_missing_index_row` (WARN) — an ADR is missing from the directory's README index (how the `0038` collision went unnoticed for a week). Repair via Step 2c instead of re-warning.

**Multiple ADR directories** (issue #2129): the guard scans a directory *set* —
the real ADR-0016 collision had its claimants in `docs/adrs/` and
`docs/blueprint/adrs/`, which a single-directory scan cannot see. Precedence:
repeatable `--adr-dir <dir>`, else `validation.adr_dirs` from the **shared**
`validation` manifest block (issue #2128, read via
`blueprint-plugin/scripts/get-validation-config.sh` — do not add a second config
mechanism), else the default `docs/adrs` then `docs/adr` order. It emits
`ADR_DIRS=` (TAB-separated) and `ADR_DIR_COUNT=`; `ADR_DIR=`, `ADR_COUNT=` and
`INDEX=` keep their #1585 meanings.

Fold findings into the Step 4 report. `STATUS=ERROR` is a blocking collision:
renumber the newer ADR to the next free number (updating **both** its filename
and its frontmatter `id:`), then regenerate the index (Step 2c).

### Step 2c: Regenerate the ADR index

`adr_missing_index_row` is repairable — the hand-maintained table is what
rotted. Rebuild it from frontmatter:

```bash
# CI / read-only gate: non-zero exit when the on-disk index is out of date
bash ${CLAUDE_SKILL_DIR}/scripts/generate-adr-index.sh --project-dir "$(pwd)" --check

# Repair: rewrite the table in every resolved ADR directory
bash ${CLAUDE_SKILL_DIR}/scripts/generate-adr-index.sh --project-dir "$(pwd)"
```

Only the block between two marker comments is rewritten, so prose around it
survives:

```markdown
<!-- ADR-INDEX:START -->
| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-0016](0016-in-engine-ui.md) | In-engine UI | Accepted |
<!-- ADR-INDEX:END -->
```

One index per directory (`--index-file` overrides the `README.md` default), over
the same directory set and widened number collection as Step 2b — so an ADR
numbered only in frontmatter still gets a row. `--check` states per directory:

| State | Severity | Meaning |
|-------|----------|---------|
| `in_sync` | OK | On-disk block matches the generated one |
| `drifted` | ERROR (exit 1) | Regenerate — the index is stale |
| `markers_absent` | WARN (exit 0) | No marker pair yet; a write adopts them. Deliberately **not** a diff |
| `index_absent` | WARN (exit 0) | No index file yet; a write creates one |
| `no_adrs` | OK | Directory holds no numbered ADRs |

Write mode reports `written` / `unchanged` / `markers_inserted` /
`index_created`. When markers land in a README that already had a hand-written
table, delete that table — the generated block is authoritative.

### Step 3: Analyze domains

1. Group ADRs by domain field
2. For each domain with multiple "Accepted" ADRs → potential conflict flag
3. List untagged ADRs (not errors, but recommendations)

### Step 4: Generate validation report

Compile comprehensive report showing:
- Summary: Total ADRs, domain-tagged %, relationship counts, status breakdown
- Reference integrity: Supersedes, extends, related status (✅/⚠️/❌)
- Errors found: Broken references, self-references, cycles
- Warnings: Outdated extensions, one-way links
- Domain analysis: Conflicts and untagged ADRs

### Step 5: Handle --report-only flag

If `--report-only` flag present:
1. Output validation report from Step 4
2. Exit without prompting for fixes

### Step 6: Prompt for remediation (if interactive mode)

Ask user action via AskUserQuestion:
- Fix all automatically (update status, add reciprocal links)
- Review each issue individually
- Export report to `docs/adrs/validation-report.md`
- Skip for now

Execute based on selection (see [REFERENCE.md](REFERENCE.md#remediation-procedures)).

### Step 7: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg result "${VALIDATION_RESULT:-success}" \
  --argjson processed "${ADRS_VALIDATED:-0}" \
  '.task_registry["adr-validate"].last_completed_at = $now |
   .task_registry["adr-validate"].last_result = $result |
   .task_registry["adr-validate"].stats.runs_total = ((.task_registry["adr-validate"].stats.runs_total // 0) + 1) |
   .task_registry["adr-validate"].stats.items_processed = $processed' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

Where `VALIDATION_RESULT` is "success", "{N} warnings", or "failed: {reason}".

### Step 8: Report changes and summary

Report all changes made:
- Updated ADRs (status changes, added links)
- Remaining issues count
- Next steps recommendation

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check ADR directory | `test -d docs/adrs && echo "YES" \|\| echo "NO"` |
| Count ADRs | `ls docs/adrs/*.md 2>/dev/null \| wc -l` |
| Extract frontmatter | `head -50 {file} \| grep -m1 "^field:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| Find by domain | `grep -l "^domain: {domain}" docs/adrs/*.md` |
| Detect cycles | Build supersession graph and traverse |
| Number collisions | `bash ${CLAUDE_SKILL_DIR}/scripts/check-adr-numbers.sh --project-dir "$(pwd)"` |
| Two ADR dirs | `… /check-adr-numbers.sh --adr-dir docs/adrs --adr-dir docs/blueprint/adrs` |
| Index drift gate (CI) | `bash ${CLAUDE_SKILL_DIR}/scripts/generate-adr-index.sh --check` |
| Regenerate index | `bash ${CLAUDE_SKILL_DIR}/scripts/generate-adr-index.sh` |

---

For validation rules, remediation procedures, and report format details, see [REFERENCE.md](REFERENCE.md).
