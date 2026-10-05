# Stage and Report Templates

Used by Step 6 (Stage files and report) of `/configure:repo`.

## Staging commands

Stage the relevant files:

```bash
git add .claude/settings.json
git add scripts/install_pkgs.sh        # if created
git add .gitattributes                 # if created/updated
git add .github/workflows/claude.yml   # if created
git add .github/workflows/claude-code-review.yml  # if created
```

## Summary template

Print a summary:

```
configure-repo complete
=======================
Repository: <repo-name>

Files staged:
  .claude/settings.json             [CREATED | UPDATED]
  scripts/install_pkgs.sh           [CREATED | UPDATED | SKIPPED]
  .github/workflows/claude.yml      [CREATED | UPDATED | SKIPPED]
  .github/workflows/claude-code-review.yml  [CREATED | UPDATED | SKIPPED]

Marketplace enrollment:
  .claude/settings.json → extraKnownMarketplaces.claude-plugins  ✓
  .github/workflows/claude.yml → plugin_marketplaces             ✓

Health check: PASS | WARN (<N> warnings) | FAIL (<N> failures)

Next steps:
  1. Review the staged diff: git diff --cached
  2. Commit: git commit -m "chore(claude): configure repo for Claude Code"
  3. Add CLAUDE_CODE_OAUTH_TOKEN to repository secrets
  4. Push and test: mention @claude in a PR comment
```
