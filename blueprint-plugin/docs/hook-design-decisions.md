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
| `## AI Documentation` | References to ai_docs |
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

### Required Markdown Sections (P0 - Blocking)

| Section | Purpose |
|---------|---------|
| `## Context` | Problem and background |
| `## Decision` | The architecture decision |
| `## Consequences` | Impact of the decision |
| `## Options Considered` | Alternatives evaluated |
| `## Related ADRs` | Links to related decisions |

## Reference Validation

### Local File References

- Check that referenced files exist
- BLOCK if files are missing
- Applies to: `ai_docs/`, `docs/`, relative paths

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

**ShellSpec** - BDD-style shell testing

```shell
Describe "validate-prp-frontmatter.sh"
  It "blocks on missing required field"
    When call validate_prp "fixtures/missing-status.md"
    The status should equal 2
    The stderr should include "ERROR: Missing required field: status"
  End
End
```

### Test Fixtures

Create test documents in `hooks/spec/fixtures/`:

- `valid-prp.md` - All requirements met
- `missing-field-prp.md` - Missing required frontmatter
- `low-confidence-prp.md` - Confidence < 7
- `missing-section-prp.md` - Missing required section
- `valid-adr.md` - Valid ADR
- `invalid-status-adr.md` - Invalid status value

## Hook Priority and Implementation

### P0 - Critical (Implement Now)

| Hook | Trigger | Action |
|------|---------|--------|
| PRP Frontmatter Validation | `Write(docs/prps/**)` | Block on invalid |
| ADR Frontmatter Validation | `Write(docs/adrs/**)` | Block on invalid |
| Execution Readiness Gate | `Skill(prp-execute)` | Block if not ready |

### P1 - Important (Plan)

| Hook | Trigger | Action |
|------|---------|--------|
| Feature Tracker Auto-Sync | `Write(docs/**)`, `Edit(docs/**)` | Sync feature-tracker.json |
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
