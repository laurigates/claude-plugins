# blueprint-work-order — Reference

Principles a work-order must meet and the error-handling table for `/blueprint:work-order`. Step-specific material lives in `references/`:

| File | Read when |
|------|-----------|
| [references/work-order-template.md](references/work-order-template.md) | Step 5 — generating the work-order body |
| [references/github-publishing.md](references/github-publishing.md) | Step 7 — publishing the issue (skipped with `--no-publish`) |
| [references/id-registry-entry.md](references/id-registry-entry.md) | Step 8.5 — updating the manifest ID registry |
| [references/report-template.md](references/report-template.md) | Step 9 — printing the report |
| [references/next-action-prompt.md](references/next-action-prompt.md) | Step 10 — the next-action prompt and its selection mapping |

## Key Principles

- **Minimal context**: Only what's needed, not full files/PRDs
- **Specific tests**: Exact test cases, not vague descriptions
- **TDD enforced**: Tests specified before implementation
- **Clear criteria**: Unambiguous success checkboxes
- **Isolated**: Task should be doable with only provided context
- **Transparent**: GitHub issue provides visibility to collaborators

## Error Handling

| Condition | Action |
|-----------|--------|
| No PRDs exist | Guide to write PRDs first |
| No tasks in feature-tracker | Ask for current phase/status |
| Task unclear | Ask user what to work on next |
| `gh` not authenticated | Warn and fallback to `--no-publish` behavior |
| Issue already has `work-order` label | Warn, ask to update or create new |
