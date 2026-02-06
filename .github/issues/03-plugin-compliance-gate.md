# Plugin Compliance Gate Workflow

## Summary

Create a GitHub Actions workflow that validates plugin metadata consistency on PRs that modify plugin configurations or skills. Ensures marketplace.json, release-please configs, and plugin.json stay synchronized.

## Motivation

The Plugin Lifecycle (documented in CLAUDE.md) requires updating multiple files when creating or modifying plugins: `plugin.json`, `marketplace.json`, `release-please-config.json`, and `.release-please-manifest.json`. This workflow automates the consistency check that `validate-plugin-configs.yml` partially covers, extended with skill quality checks via Claude.

## Scope

### Workflow: `.github/workflows/plugin-compliance.yml`

**Trigger:** Pull requests that touch `**/.claude-plugin/**`, `**/skills/**`, or `**/agents/**`

**Steps:**
1. **Plugin Metadata Sync:** Verify each plugin has matching entries in:
   - `.claude-plugin/plugin.json` (exists with required fields)
   - `.claude-plugin/marketplace.json` (entry exists, version matches)
   - `release-please-config.json` (package configured)
   - `.release-please-manifest.json` (version tracked)
2. **Skill Quality Gate:** For changed SKILL.md files, verify:
   - Agentic optimization tables present (for CLI/tool skills)
   - `allowed-tools` uses granular `Bash(command *)` patterns
   - Model selection is appropriate (haiku for tools, opus for reasoning)
3. **Permission Audit:** Check that new/modified skills follow least-privilege patterns

**Model:** `haiku` (checklist verification against known rules)

**Permissions:** `contents: read`, `pull-requests: write`

### Relationship to Existing Workflows

- **Extends** `validate-plugin-configs.yml` (which does basic JSON sync)
- **Extends** `skill-quality-review.yml` (which checks skill content quality)
- **Combines** both into a unified compliance gate with broader scope

### Implementation Details

- Uses `anthropics/claude-code-action@v1`
- `--model haiku --max-turns 15`
- Posts PR review comments on specific files with violations
- Reuses patterns from `/configure:status` for compliance checking

### Decision: Separate vs Merged

Consider whether this should:
- (a) Be a new standalone workflow
- (b) Extend `validate-plugin-configs.yml` with a Claude step
- (c) Extend `skill-quality-review.yml` to also check metadata

**Recommendation:** Option (b) — add a Claude-powered step to the existing validation workflow

### Acceptance Criteria

- [ ] Validates plugin metadata consistency across all 4 config files
- [ ] Checks skill quality on changed SKILL.md files
- [ ] Audits permission patterns in skill frontmatter
- [ ] Posts actionable PR review comments
- [ ] Integrates cleanly with existing validation workflows
- [ ] No false positives on well-configured plugins

## Labels

`enhancement`, `github-actions`, `plugin-infrastructure`
