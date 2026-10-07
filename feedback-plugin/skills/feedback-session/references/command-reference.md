# feedback-session: command and flag reference

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List feedback issues | `gh issue list --label session-feedback --json number,title,labels -q '.[]'` |
| Search for duplicates | `gh issue list --label session-feedback --search "keyword" --json title -q '.[].title'` |
| Detect IaC label signals | `gh label list --json name,description --jq '.[].description'` |
| Check label exists | `gh label list --json name -q '.[].name'` |
| Create label | `gh label create name --description "desc" --color "hex"` |
| Create issue (with target) | `gh issue create -R owner/repo --title "t" --label "l1,l2" --body "b"` |
| Create issue (no labels) | `gh issue create -R owner/repo --title "t" --body "b"` |
| Infer current repo | `gh repo view --json nameWithOwner -q '.nameWithOwner'` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--dry-run` | Show findings without creating issues |
| `--bugs-only` | Only bug reports |
| `--enhancements-only` | Only enhancement suggestions |
| `--positive-only` | Only positive feedback |
| `--target-repo <owner/repo>` | File issues against a different repo (e.g. plugin source) |
| `-R <owner/repo>` | Alias for `--target-repo` |
| `[plugin-name]` | Scope to specific plugin |
| `<freeform prose>` | Explicit seed finding(s) to file; coexists with flags |
