# Release-Please Workflow Guide

Complete guide to using Google's release-please automation for version management and changelog generation.

## What is Release-Please?

Release-please is a GitHub Action that:
- **Automatically generates CHANGELOGs** from conventional commit messages
- **Determines version bumps** based on commit types (semver)
- **Creates release PRs** with all changes grouped together
- **Tags releases** when the PR is merged
- **Publishes packages** to registries (if configured)

**Key benefit:** Zero manual intervention for version management and changelog updates.

---

## The Problem With Manual Edits

### Why Manual CHANGELOG.md Edits Fail

```
You: edit CHANGELOG.md manually
Release-please: creates PR updating CHANGELOG.md automatically

Result: MERGE CONFLICT 💥

GitHub blocks the PR because:
- Both changes modify the same file
- Release-please can't auto-merge
- You must manually resolve conflicts
- Your manual entry might be duplicated or lost
```

### Why Manual Version Bumps Fail

```
You: change version in package.json from 1.0.0 → 1.1.0
Release-please: analyzes commits, determines version should be 1.0.1

Result: VERSION MISMATCH 💥

Consequences:
- Release-please overwrites your manual bump
- Version history becomes inconsistent
- Semantic versioning is violated
- Dependency tracking breaks
```

---

## The Correct Workflow

### Step 1: Make Your Changes

Work normally - write code, fix bugs, add features:

```bash
# Make your changes
vim src/auth.ts

# Stage changes
git add src/auth.ts
```

### Step 2: Write a Conventional Commit

Use **conventional commit format** to describe your change:

```bash
git commit -m "feat(auth): add OAuth2 support

Implements OAuth2 authentication flow with PKCE.
Includes refresh token rotation and session management.

Refs: #42"
```

**Conventional commit format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Step 3: Push to Remote

```bash
git push origin main
# or push to feature branch and create PR
```

### Step 4: Release-Please Activates

After your commit is merged to main branch:

1. **Release-please analyzes new commits** since last release
2. **Determines version bump** based on commit types:
   - `feat:` → minor version bump (1.0.0 → 1.1.0)
   - `fix:` → patch version bump (1.0.0 → 1.0.1)
   - `feat!:` or `BREAKING CHANGE:` → major version bump (1.0.0 → 2.0.0)
   - `chore:`, `docs:`, `style:` → no version bump

3. **Creates or updates a release PR** containing:
   - CHANGELOG.md with new entries
   - package.json (or equivalent) with new version
   - All other version-managed files updated

### Step 5: Review the Release PR

Release-please creates a PR like:

```
Title: chore(main): release 1.1.0

Changes:
- CHANGELOG.md: added entries for new features
- package.json: version bumped from 1.0.0 → 1.1.0
- Cargo.toml: version bumped from 1.0.0 → 1.1.0
```

**What you should review:**
- ✅ Version number is correct for the changes
- ✅ CHANGELOG entries accurately describe commits
- ✅ All version files are updated consistently
- ✅ No unexpected changes included

### Step 6: Merge the Release PR

```bash
# Via GitHub UI: click "Merge pull request"
# Or via CLI:
gh pr merge <PR-number> --squash
```

### Step 7: Release-Please Creates Tagged Release

After merge:
- 📦 Creates Git tag (e.g., `v1.1.0`)
- 🎉 Creates GitHub Release with CHANGELOG notes
- 🚀 Triggers any publish workflows (npm, crates.io, etc.)

---

## Conventional Commit Types

### `feat:` - New Feature (Minor Version Bump)

Adds new functionality visible to users.

**Example:**
```bash
git commit -m "feat(api): add user profile endpoints

Implements GET/POST/PUT/DELETE operations for user profiles.
Includes validation and error handling.

Refs: #123"
```

**Version impact:** 1.2.3 → 1.3.0

**Use when:**
- Adding new API endpoints
- Implementing new user-facing features
- Adding new configuration options
- Expanding capabilities

---

### `fix:` - Bug Fix (Patch Version Bump)

Fixes incorrect behavior without adding new features.

**Example:**
```bash
git commit -m "fix(auth): prevent token refresh race condition

Fixes issue where multiple concurrent requests could
trigger simultaneous token refreshes, causing 401 errors.

Fixes: #456"
```

**Version impact:** 1.2.3 → 1.2.4

**Use when:**
- Fixing bugs
- Resolving security vulnerabilities
- Correcting incorrect behavior
- Patching edge cases

---

### `feat!:` or `BREAKING CHANGE:` - Breaking Change (Major Version Bump)

Changes that break backwards compatibility.

**Example:**
```bash
git commit -m "feat(api)!: redesign authentication flow

BREAKING CHANGE: The authentication endpoint now requires
OAuth2 instead of API keys. Users must migrate their
integrations to use the new /oauth/token endpoint.

Migration guide: docs/migration/v2.md

Refs: #789"
```

**Version impact:** 1.2.3 → 2.0.0

**Use when:**
- Removing public APIs
- Changing API signatures
- Modifying configuration schemas
- Requiring new dependencies

---

### `chore:` - Maintenance (No Version Bump)

Internal changes that don't affect users.

**Example:**
```bash
git commit -m "chore(deps): update development dependencies

Updates test frameworks and linting tools to latest versions.
No user-facing changes."
```

**Version impact:** No change

**Use when:**
- Updating dev dependencies
- Refactoring internal code
- Updating CI/CD configs
- Improving build processes

---

### Other Types (No Version Bump)

- `docs:` - Documentation only changes
- `style:` - Code style/formatting (no logic changes)
- `refactor:` - Code refactoring (no behavior change)
- `perf:` - Performance improvements (if no breaking changes)
- `test:` - Adding or updating tests
- `build:` - Build system changes
- `ci:` - CI/CD configuration changes

---

## Scope Guidelines

The `<scope>` is optional but helps organize changelogs:

**Good scopes:**
- `(auth)` - Authentication system
- `(api)` - API endpoints
- `(cli)` - Command-line interface
- `(ui)` - User interface
- `(db)` - Database layer
- `(plugin-core)` - Core plugin for Claude Code

**Avoid:**
- Generic scopes like `(misc)`, `(stuff)`
- File names like `(index.js)`
- Too specific like `(line-47-fix)`

---

## Multi-Paragraph Commit Messages

For complex changes, use detailed commit messages:

```bash
git commit -m "feat(plugins): add plugin marketplace support

Implements local plugin marketplace for Claude Code plugins.
Users can now distribute plugins via directory-based marketplaces.

Key features:
- Plugin manifest schema with versioning
- Marketplace registration in settings.json
- Automatic plugin discovery and loading
- Version conflict resolution

Technical notes:
- Uses plugin.json schema v1.0
- Marketplace path can be relative or absolute
- Supports nested plugin directories

Refs: #101, #102
Co-authored-by: AI Assistant <ai@example.com>"
```

This generates detailed CHANGELOG entries.

---

## Working with Multiple Commits

Release-please groups all commits since the last release:

```
Last release: v1.0.0

Commits since then:
1. feat(auth): add OAuth2           → Triggers 1.1.0
2. fix(auth): handle edge case      → Already triggering 1.1.0
3. docs: update README              → No version bump
4. feat(api): add webhooks          → Still 1.1.0 (not 1.2.0)

Result: One release PR with v1.1.0
```

**Release-please creates ONE release PR** containing all changes.

**If you want separate releases:**
```bash
# Option 1: Merge release PR after each feature
git commit -m "feat(auth): add OAuth2"
git push
# Wait for release PR, merge it
# Now next feature gets its own release

# Option 2: Use release branches (advanced)
# Configure release-please to track multiple branches
```

---

## Handling Edge Cases

### Emergency Hotfix (Skip Normal Process)

Sometimes you need to release immediately:

```bash
# 1. Make critical fix
git commit -m "fix(security): patch CVE-2024-12345

Critical security fix for XSS vulnerability.

GHSA-xxxx-yyyy-zzzz"

# 2. Push to main
git push origin main

# 3. Manually trigger release workflow (if configured)
gh workflow run release-please.yml

# 4. Merge release PR immediately
# 5. Wait for tagged release and deployment
```

**Or manually bump if release-please is blocked:**
```bash
# Only use this if release-please is completely broken

# 1. Comment out CHANGELOG.md deny rules in ~/.claude/settings.json
# 2. Manually edit version and CHANGELOG.md
# 3. Commit as chore: (won't trigger release-please)
git commit -m "chore(release): emergency hotfix v1.0.1"
# 4. Push and tag manually
git tag v1.0.1
git push origin main --tags
# 5. Restore deny rules
```

### Sync Drift (Manual Edit Was Made)

If someone manually edited version/CHANGELOG:

```bash
# 1. Pull latest changes
git pull origin main

# 2. Check release-please PR
gh pr view <release-PR-number>

# 3. If conflicts exist:
gh pr checkout <release-PR-number>

# 4. Resolve conflicts preferring release-please changes
git checkout --theirs CHANGELOG.md package.json
git add CHANGELOG.md package.json
git commit -m "chore: resolve release-please conflicts"
git push

# 5. Merge release PR
gh pr merge <release-PR-number>

# 6. Future: prevent manual edits via this skill
```

### Force Version Bump (Override Semantic Versioning)

Release-please usually determines versions automatically, but you can override:

**Method 1: Config file** (`.release-please-config.json`)
```json
{
  "packages": {
    ".": {
      "release-type": "simple",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": false,
      "version": "2.0.0"  // Forces next release to be 2.0.0
    }
  }
}
```

**Method 2: Commit message footer**
```bash
git commit -m "feat(api): add new endpoints

Release-As: 2.0.0"
```

**Use sparingly** - defeats the purpose of automation.

---

## Multi-Package Repositories (Monorepos)

If you have multiple packages in one repo:

**.release-please-config.json:**
```json
{
  "packages": {
    "plugins/dotfiles-core": {
      "release-type": "simple",
      "package-name": "dotfiles-core",
      "changelog-path": "CHANGELOG.md"
    },
    "plugins/dotfiles-toolkit": {
      "release-type": "simple",
      "package-name": "dotfiles-toolkit",
      "changelog-path": "CHANGELOG.md"
    }
  }
}
```

**Commits specify package:**
```bash
# Scoped commits determine which package releases
git commit -m "feat(dotfiles-core): add new agent"
# Only dotfiles-core gets a release

git commit -m "feat(dotfiles-toolkit): update command"
# Only dotfiles-toolkit gets a release

git commit -m "feat: update shared configuration"
# Affects all packages (root release)
```

---

## Debugging Release-Please

### Check workflow runs:
```bash
gh run list --workflow=release-please.yml
gh run view <run-id> --log
```

### Verify configuration:
```bash
cat .release-please-config.json
cat .release-please-manifest.json
```

### Test commit parsing:
```bash
# Check if commits follow conventional format
git log --oneline | head -10

# View release-please PR if it exists
gh pr list --label "autorelease: pending"
```

### Common issues:

**No release PR created:**
- Check if commits follow conventional format
- Verify workflow file exists (`.github/workflows/release-please.yml`)
- Check workflow permissions (needs write access to PRs)
- Look for errors in workflow runs

**Wrong version bump:**
- Review commit messages - type determines bump
- Check for accidental BREAKING CHANGE footers
- Verify release-please config for overrides

**CHANGELOG.md conflicts:**
- Someone manually edited CHANGELOG.md
- Merge release PR and resolve conflicts favoring release-please version
- Enable this protection skill to prevent future manual edits

---

## Best Practices

### ✅ Do This

- Write clear, descriptive commit messages
- Use appropriate conventional commit types
- Group related changes in single commits
- Review release PRs before merging
- Keep commits atomic (one logical change each)
- Use multi-paragraph messages for complex changes

### ❌ Don't Do This

- Manually edit CHANGELOG.md
- Manually bump version numbers
- Use generic commit messages ("fix stuff")
- Mix breaking and non-breaking changes in one commit
- Bypass conventional commit format
- Edit release PRs after creation (let release-please regenerate)

---

## Integration with Claude Code

This skill enforces proper workflow by:

1. **Blocking CHANGELOG.md edits** via permission system
2. **Warning on version field modifications** before they happen
3. **Suggesting conventional commits** when version bumps requested
4. **Providing commit templates** matching user intent
5. **Explaining conflicts** when automation fails

**When Claude suggests conventional commits:**

```
You: "Bump version to add new authentication feature"

Claude (this skill):
⚠️ Instead of manually bumping the version, I'll help you create
a conventional commit that will trigger release-please to bump
the version automatically.

Suggested commit:
---
feat(auth): add OAuth2 authentication support

Implements OAuth2 2.0 authentication flow with PKCE.
Supports authorization code grant with refresh tokens.

Features:
- Token refresh handling
- Session management
- Secure state validation

Refs: #issue-number
---

This will trigger a minor version bump (X.Y.0) when merged.
Would you like me to create this commit?
```

---

## Further Resources

- **Release-Please Documentation:** https://github.com/googleapis/release-please
- **Conventional Commits Spec:** https://www.conventionalcommits.org/
- **Semantic Versioning:** https://semver.org/
- **GitHub Actions Integration:** https://github.com/googleapis/release-please/tree/main/docs
- **Config Schema:** https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md

---

**Last updated:** 2025-10-29
**Part of:** release-please-protection skill for Claude Code
