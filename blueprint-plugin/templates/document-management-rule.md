# Document Management

Rules for organizing and managing project documentation.

## Document Types and Locations

| Document Type | Directory | Naming Convention | Purpose |
|--------------|-----------|-------------------|---------|
| PRD | `docs/prds/` | `{feature-name}.md` | Product Requirements Documents |
| ADR | `docs/adrs/` | `{number}-{title}.md` | Architecture Decision Records |
| PRP | `docs/prps/` | `{feature-name}.md` | Product Requirement Prompts |

### Examples

```
docs/
├── prds/
│   ├── user-authentication.md
│   ├── payment-processing.md
│   └── dashboard-redesign.md
├── adrs/
│   ├── 0001-database-choice.md
│   ├── 0002-api-framework.md
│   └── 0003-state-management.md
└── prps/
    ├── oauth-integration.md
    └── stripe-checkout.md
```

## Root Directory Policy

The repository root should contain only:

### Allowed Files
- `README.md` - Project overview and quick start
- `CHANGELOG.md` - Release notes (often auto-generated)
- `LICENSE` or `LICENSE.md` - License file
- `CONTRIBUTING.md` - Contribution guidelines
- `CODE_OF_CONDUCT.md` - Community guidelines
- `SECURITY.md` - Security policy
- Configuration files (package.json, Cargo.toml, pyproject.toml, etc.)
- Build/CI configuration (.github/, Makefile, Justfile, etc.)

### Not Allowed in Root
- Requirements documents (move to `docs/prds/`)
- Architecture documents (move to `docs/adrs/`)
- Design documents (move to `docs/` or appropriate subdirectory)
- API documentation (move to `docs/api/`)
- Technical specifications (move to `docs/specs/`)

## Document Lifecycle

### 1. Detection
Claude identifies documentation opportunities during conversation:
- Feature discussions trigger PRD detection
- Architecture debates trigger ADR detection
- Implementation planning triggers PRP detection

### 2. Confirmation
User approves document creation via AskUserQuestion prompt:
- "Yes, create [document type]" - Proceed with creation
- "Not now, remind me later" - Defer, re-prompt if topic expands
- "No, just continue" - Skip documentation

### 3. Generation
Document created in appropriate location:
- PRD: `docs/prds/{feature-name}.md`
- ADR: `docs/adrs/{number}-{title}.md`
- PRP: `docs/prps/{feature-name}.md`

### 4. Review
User reviews and refines generated document:
- Verify accuracy of captured requirements
- Add missing details or constraints
- Correct any misunderstandings

### 5. Tracking
Manifest updated with document metadata:
- Document type and location
- Creation timestamp
- Related documents linked

## Automatic Detection

When `has_document_detection` is enabled, Claude will proactively prompt to create:

| Conversation Type | Document Suggested |
|-------------------|-------------------|
| Feature requirements discussed | PRD |
| Architecture decisions debated | ADR |
| Implementation approach planned | PRP |

### Enable/Disable

Configure in `docs/blueprint/manifest.json`:

```json
{
  "structure": {
    "has_document_detection": true
  }
}
```

To enable: Run `/blueprint:init` or `/blueprint:upgrade` and select the document detection option.

To disable: Set `has_document_detection: false` in manifest.

## ADR Numbering

ADRs use sequential numbering with zero-padded 4-digit prefixes:

```
0001-database-choice.md
0002-api-framework.md
0003-state-management.md
```

To find next ADR number:
```bash
ls docs/adrs/ | grep -E '^[0-9]{4}-' | sort -r | head -1 | cut -d'-' -f1
```

## Cross-Referencing

### PRD to ADR
When a PRD references an architecture decision:
```markdown
## Technical Decisions

See [ADR-0001: Database Choice](../adrs/0001-database-choice.md) for database selection rationale.
```

### PRP to PRD
When a PRP implements requirements from a PRD:
```markdown
## Source Requirements

This PRP implements requirements from [User Authentication PRD](../prds/user-authentication.md).
```

### ADR to PRD
When an ADR affects specific features:
```markdown
## Affected Features

This decision impacts:
- [User Authentication](../prds/user-authentication.md)
- [Payment Processing](../prds/payment-processing.md)
```

## Migration from Root

If documentation files exist in the repository root, migrate them:

1. Identify files: `REQUIREMENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`, etc.
2. Analyze content to determine document type
3. Move to appropriate `docs/` subdirectory
4. Update any internal links
5. Update references in other documents

Run `/blueprint:init` or `/blueprint:upgrade` to be prompted for migration.
