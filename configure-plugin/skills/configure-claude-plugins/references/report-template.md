# Configuration Report Template

Used by Step 6 (Report results) of `/configure:claude-plugins`.

Print a status report:

```
Claude Plugins Configuration Report
=====================================
Repository: <repo-name>

.claude/settings.json:
  Status:              <CREATED|UPDATED|EXISTS>
  Mode:                <DEFAULT|EXHAUSTIVE>
  Permissions:         <N> allowed patterns configured
  Marketplace:         laurigates/claude-plugins (extraKnownMarketplaces)
  Plugins pinned:      <N> total (<E> enabled, <D> disabled)   # exhaustive only
  Enabled plugins:     <list>

Git remote:            <PRESENT|MISSING>

.github/workflows/claude.yml:
  Status:              <CREATED|UPDATED|EXISTS|SKIPPED (no git remote)|SKIPPED (--no-workflows)>
  Marketplace:         laurigates/claude-plugins
  Plugins:             <list>

.github/workflows/claude-code-review.yml:
  Status:              <CREATED|UPDATED|EXISTS|SKIPPED (no git remote)|SKIPPED (--no-workflows)>
  Trigger:             PR opened/synchronize/reopened

Next Steps:
  1. Add CLAUDE_CODE_OAUTH_TOKEN to repository secrets
     Settings > Secrets and variables > Actions > New repository secret
  2. Commit and push the new/updated files
  3. Test by mentioning @claude in a PR comment
  4. (exhaustive mode) Re-run when the marketplace adds new plugins so they
     get an explicit `false` rather than inheriting the global toggle
  5. (no remote) When you add a GitHub remote later, re-run with `--workflows`
     to scaffold the workflows that were skipped
```
