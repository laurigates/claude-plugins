# Document IDs and Traceability

This project uses a unified ID system connecting requirements, decisions, implementations, and GitHub issues.

## ID Formats

| Type | Format | Example |
|------|--------|---------|
| PRD | `PRD-NNN` | `PRD-001` |
| ADR | `ADR-NNNN` | `ADR-0003` |
| PRP | `PRP-NNN` | `PRP-007` |
| Work-Order | `WO-NNN` | `WO-042` |

## Document Frontmatter

All blueprint documents include linking fields:

```yaml
---
id: PRD-001
relates-to:
  - ADR-0003
github-issues:
  - 42
---
```

PRPs include implementation tracking:

```yaml
---
id: PRP-002
implements:
  - PRD-001
---
```

## GitHub Conventions

### Issue Titles

Prefix with document ID:
- `[PRD-001] User authentication feature`
- `[WO-042] Implement JWT token generation`

### Commit Messages

Use document ID in scope:
- `feat(PRD-001): add login component`
- `fix(PRP-002): correct OAuth callback URL`

### PR References

Include document IDs and issue links:
```
Implements PRD-001
Related: ADR-0003
Fixes #42
```

## Querying Links

Find related documents:
```bash
# Documents linked to PRD-001
jq '.id_registry.documents["PRD-001"]' docs/blueprint/manifest.json

# All GitHub issues for a document
jq '.id_registry.documents["PRD-001"].github_issues' docs/blueprint/manifest.json
```

## Commands

| Task | Command |
|------|---------|
| Assign missing IDs | `/blueprint:sync-ids` |
| View traceability | `/blueprint:status` |
| Link doc to issue | Edit frontmatter `github-issues` array |
