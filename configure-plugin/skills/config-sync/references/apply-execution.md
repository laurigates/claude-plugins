# Apply Execution

Used by Apply Step 5 when creating branches, commits, and PRs in target repos.

For each target repo:

1. Create a branch: `config-sync/<filename-slug>`
2. Copy/update the file
3. Commit with conventional message: `chore: sync <filename> from <source-repo>`
4. Push and create PR via `gh pr create`

```bash
cd /Users/lgates/repos/ForumViriumHelsinki/<target-repo>
git checkout -b config-sync/claude-yml
# ... apply changes ...
git add <file>
git commit -m "chore: sync claude.yml from canonical

Co-Authored-By: Claude <noreply@anthropic.com>"
git push -u origin config-sync/claude-yml
gh pr create --title "chore: sync claude.yml" --body "$(cat <<'EOF'
## Summary
- Synced `.github/workflows/claude.yml` to match canonical version
- Source: most common version across 18 repos

## Changes
<inline diff>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Inside a quoted heredoc (`<<'EOF'`), backticks, `$`, and `\` are already literal — never backslash-escape them.** A stray `\`` lands in the rendered PR body and needs a follow-up `gh pr edit` to fix. To skip the `$(cat ...)` subshell entirely, feed the body straight to `gh` over stdin:

```bash
gh pr create --title "chore: sync claude.yml" --body-file - <<'EOF'
## Summary
- Synced `.github/workflows/claude.yml` to match canonical version
EOF
```
