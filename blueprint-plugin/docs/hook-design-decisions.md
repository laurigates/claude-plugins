# Blueprint Hook Validation Gates - Design Decisions

This document captures design decisions for implementing validation hooks in the blueprint plugin.

## Architecture Decisions

### Failure Mode

**Decision**: Strict (block on P0, warn on P1+)

- P0 hooks (frontmatter validation, execution readiness) BLOCK operations on failure
- P1+ hooks WARN but allow operation to continue
- Rationale: Critical quality gates must be enforced; lower priority checks are advisory

### Hook Location

**Decision**: Self-contained in `blueprint-plugin/hooks/`

- All hook scripts live in `blueprint-plugin/hooks/`
- Keeps plugin portable and self-contained
- No dependency on hooks-plugin

### Message Format

**Decision**: Structured prefix format

```
ERROR: <message>   # Critical issues that block
WARNING: <message> # Advisory issues, non-blocking
INFO: <message>    # Informational output
```

- Easy to parse programmatically
- Clear severity indication
- Consistent across all hooks

### Bypass Mode

**Decision**: Environment variable `BLUEPRINT_SKIP_HOOKS=1`

- Single env var disables all blueprint hooks
- For emergency situations only
- Example: `BLUEPRINT_SKIP_HOOKS=1 claude code`

### Timeouts

**Decision**: Fixed per-hook type

| Hook Type | Timeout |
|-----------|---------|
| Frontmatter validation | 3000ms |
| Execution readiness | 5000ms |
| Network operations (URL check) | 5000ms per URL, 10000ms total |
| Auto-sync operations | 5000ms |

## PRP Validation Rules

### Required Frontmatter Fields (P0 - Blocking)

All PRPs MUST have these fields:

| Field | Description |
|-------|-------------|
| `created` | Creation date (YYYY-MM-DD) |
| `modified` | Last modification date |
| `reviewed` | Last review date |
| `status` | draft, ready, in-progress, completed |
| `confidence` | Score out of 10 (e.g., "7/10") |
| `domain` | Feature domain/area |
| `feature-codes` | Array of feature codes |
| `related` | Related documents |

### Required Markdown Sections (P0 - Blocking)

PRPs MUST contain these sections:

| Section | Purpose |
|---------|---------|
| `## Context Framing` | Background and problem statement |
| `## AI Documentation` | References to curated AI context (`.claude/rules/` entries; formerly ai_docs) |
| `## Implementation Blueprint` | Technical implementation plan |
| `## Test Strategy` | Testing approach |
| `## Validation Gates` | Quality checkpoints |
| `## Success Criteria` | Definition of done |

### Confidence Gate

**Minimum Score**: 7/10 required for execution

- PRPs with `confidence` < 7 cannot be executed via `/blueprint:prp-execute`
- Rationale: Lower confidence indicates unresolved questions or incomplete research

### Review Staleness

**Threshold**: 30 days

- WARNING if `reviewed` date is older than 30 days
- Suggests running `/blueprint:prp-create` to refresh context

## ADR Validation Rules

### Valid Status Values

Extended status set:

| Status | Description |
|--------|-------------|
| `Draft` | Initial exploration |
| `Proposed` | Ready for review |
| `Accepted` | Approved and active |
| `Rejected` | Considered but declined |
| `Withdrawn` | Cancelled before decision |
| `Superseded` | Replaced by newer ADR |
| `Deprecated` | No longer recommended |

### Markdown Sections (WARN, never blocking)

Required — a missing one emits `SEVERITY=WARN`, not a block
(`.claude/rules/hook-block-vs-nudge.md`):

| Section | Purpose |
|---------|---------|
| `## Context` | Problem and background |
| `## Decision` | The architecture decision |
| `## Consequences` | Impact of the decision |

Recommended but **unenforced** since ADR-0023 — nothing checks for these:

| Section | Purpose |
|---------|---------|
| `## Options Considered` | Alternatives evaluated |
| `## Related ADRs` | Links to related decisions |

## Reference Validation

### Local File References

- Check that referenced files exist
- BLOCK if files are missing
- Applies to: `.claude/rules/`, legacy `ai_docs/`, `docs/`, relative paths

### URL References

- HTTP HEAD request with 5s timeout
- WARN on unreachable URLs (don't block)
- Rationale: External URLs may be temporarily unavailable

### Git State

- No git state checking (keeps hooks simple)
- Users manage their own commit workflow

## Configuration

### Per-Project Configuration

Location: `.blueprint/hooks.json`

```json
{
  "enabled": true,
  "overrides": {
    "prp_confidence_threshold": 7,
    "review_staleness_days": 30,
    "adr_valid_statuses": ["Draft", "Proposed", "Accepted", "Rejected", "Withdrawn", "Superseded", "Deprecated"]
  }
}
```

### Default Behavior

- Hooks enabled by default when plugin is installed
- No configuration required for standard behavior

## Testing Strategy

### Framework

**Plain-bash `hooks/test-<hook-name>.sh`**, auto-discovered by
`scripts/run-skill-script-tests.sh` via its `*/hooks/test-*.sh` glob — so a new
suite is executed by CI and `just` the moment it is added, with no wiring.

Model a new suite on
[`hooks/test-blueprint-structural-cue.sh`](../hooks/test-blueprint-structural-cue.sh):
feed the hook the harness's **real** event JSON on stdin, assert on the emitted
JSON with `jq`, and run each case against a scratch `HOME`/cache dir.

```bash
bash blueprint-plugin/hooks/test-blueprint-structural-cue.sh   # one suite
./scripts/run-skill-script-tests.sh                            # every suite
```

> **ShellSpec was the original plan and it never ran.** The BDD specs under
> `hooks/spec/` were **aspirational**: `shellspec` is not installed, not in CI,
> not in any `just` recipe, and `spec/` matches no glob in
> `run-skill-script-tests.sh`. That is not a cosmetic gap — a never-executed suite
> is worse than none, because it reads as coverage. `spec/blueprint_structural_cue_spec.sh`
> asserted `output should include updatedToolOutput` and thereby **pinned a broken
> output shape** while the hook it "covered" was a silent no-op for weeks; it was
> retired under issue #2275 and replaced by `hooks/test-blueprint-structural-cue.sh`.
> The last four were removed when the hooks they described were rewired:
> `check_prp_readiness_spec.sh` was ported to `hooks/test-check-prp-readiness.sh`,
> and the three `validate_*_frontmatter_spec.sh` specs went with the PreToolUse
> validators they covered (validation now runs through `validate-frontmatter.sh`,
> pinned by `scripts/tests/test-check-schema.sh`).

### Test Fixtures

The frontmatter-validator documents under `hooks/spec/fixtures/` are still on
disk and still valid inputs — but no suite reads them any more. A ported suite may reuse them by path; a new one should
create its fixtures in a `mktemp -d` scratch tree, as
`test-blueprint-structural-cue.sh` does, so the suite is self-contained.

- `valid-prp.md` - All requirements met
- `missing-field-prp.md` - Missing required frontmatter
- `low-confidence-prp.md` - Confidence < 7
- `valid-adr.md` - Valid ADR
- `invalid-status-adr.md` - Invalid status value
- `valid-prd.md`, `missing-id-prd.md`, `invalid-id-prd.md` - PRD ID validation

## Hook Priority and Implementation

The **Trigger** column is written in permission-rule notation for readability.
It is not a `matcher` value: a matcher is tested against the tool name only, so
`"matcher": "Write(docs/adrs/**)"` is an invalid regex that never fires — the
state every path-scoped blueprint hook shipped in. Implement a path trigger with
a tool-name matcher plus either the handler's `if` field or a filter in the
script; for document edits, extend `hooks/blueprint-doc-change.sh`, which also
sees Bash edits. `scripts/check-hook-matchers.sh` rejects the notation in
`hooks.json`.

### P0 - Critical (Implemented)

| Hook | Trigger | Action |
|------|---------|--------|
| PRD/PRP/ADR Schema Check | `Write\|Edit\|Bash` → `docs/{prds,prps,adrs}/*.md` | Warn via PostToolUse `additionalContext`; the `blueprint-doc-schemas` pre-commit hook blocks the commit |
| Execution Readiness Gate | `Skill` → `prp-execute` (filtered in the script) | Block if not ready |

### P1 - Important

| Hook | Trigger | Action |
|------|---------|--------|
| Feature Tracker Auto-Sync (implemented) | `Write\|Edit\|Bash` → `docs/**` | Sync feature-tracker.json |
| Stale Content Detection | `Read(docs/blueprint/ai_docs/**)` | Warn if > 90 days old |

### P2 - Nice to Have (Plan)

| Hook | Trigger | Action |
|------|---------|--------|
| CLAUDE.md Interactive Sync | `Write(docs/prds/**)` | AskUserQuestion with diff hints |
| ADR Conflict Detection | `Write(docs/adrs/**)` | Warn on domain conflicts |

### P3 - Future (Plan)

| Hook | Trigger | Action |
|------|---------|--------|
| Dependency Change Watcher | `Edit(bun.lockb)`, `Edit(uv.lock)`, `Edit(Cargo.lock)` | Warn about ai_docs drift |

## Package Manager Support

For P3 Dependency Change Watcher:

| Package Manager | Lock File | Manifest |
|-----------------|-----------|----------|
| Bun | `bun.lockb` | `package.json` |
| uv | `uv.lock` | `pyproject.toml` |
| Cargo | `Cargo.lock` | `Cargo.toml` |

## P2: CLAUDE.md Interactive Sync

**Special Behavior**: Uses `AskUserQuestion` tool

When PRD changes detected:
1. Analyze diff between PRD changes and current CLAUDE.md
2. Present selectable diff hints as AskUserQuestion options
3. User selects which changes to incorporate
4. CLAUDE.md updated based on selections
5. If no selections, no changes made

This provides user control over CLAUDE.md evolution while surfacing relevant updates.
